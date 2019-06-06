#==================================================================================
# Script: 	Discover-VirtualCenter.ps1
# Date:		21/01/19
# Author: 	Andi Patrick
# Purpose:	Discovers Additional Properties for Virtual Center
#==================================================================================

# Get the named parameters
Param(
	$sourceId, 
	$managedEntityId, 
    [string]$vCenterFullName, 
    [string]$IpAddress, 
    [string]$UserName, 
    [string]$Password, 
    [string]$Debug 
)

# Get Start Time For Script
$StartTime = (GET-DATE)

#Constants used for event logging
$SCRIPT_NAME			= 'Discover-VirtualCenter.ps1'
$EVENT_LEVEL_ERROR 		= 1
$EVENT_LEVEL_WARNING 	= 2
$EVENT_LEVEL_INFO 		= 4

$SCRIPT_STARTED				= 4641
$SCRIPT_DISCOVERY_CREATED	= 4642
$SCRIPT_EVENT				= 4643
$SCRIPT_ENDED				= 4644
$SCRIPT_ERROR				= 4645

#==================================================================================
#= Declare Our Script Block That the Job will Run
#==================================================================================
$DiscoverVirtualCenter = {

    Param(
	    [string]$vCenterFullName, 
		[string]$IpAddress, 
        [string]$UserName, 
        [string]$Password, 
        [string]$Debug
    )   
	#Constants used for event logging
	$SCRIPT_NAME			= 'Discover-VirtualCenter.ps1'
	$EVENT_LEVEL_ERROR 		= 1
	$EVENT_LEVEL_WARNING 	= 2
	$EVENT_LEVEL_INFO 		= 4

	$SCRIPT_STARTED				= 4641
	$SCRIPT_DISCOVERY_CREATED	= 4642
	$SCRIPT_EVENT				= 4643
	$SCRIPT_ENDED				= 4644
	$SCRIPT_ERROR				= 4645

    #Start by setting up API object.
    $api = New-Object -comObject 'MOM.ScriptAPI'

	#
    # Import PowerCLI Modules
    Try {
	    Import-Module VMware.VimAutomation.Core
    } Catch {
	    $message = "Error Importing PowerCLI Mudules" + "`r`n" + $_
	    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
	    Exit
    }

    #
    # Connect to Virtual Centerr
    Try {
	    $vc = Connect-VIServer $vCenterFullName -User $UserName -Password $Password -Force:$true -NotDefault	
    } Catch {
		$message = "Error Connecting to Virtual Center" + "`r`n" + $_
		$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		Exit		
    }

    If ($vc) {
		# At this point Modules Should be loaded and vCenter Connected
		Try {
			# Create Virtual Center Object
			$vcObject = [PSCustomObject]@{
				FullName = $vCenterFullName
				ShortName = $vCenterFullName.Split(".")[0]
				IpAddress = $IpAddress
				ProductFullName = $vc.ExtensionData.Content.About.FullName
				ProductShortName = $vc.ExtensionData.Content.About.Name
				Version = $vc.ExtensionData.Content.About.Version
				Build = $vc.ExtensionData.Content.About.Build
				OsType = $vc.ExtensionData.Content.About.OsType
            }
			# Return it
			$vcObject


		} Catch {
			$message = "Error Getting Info from Virtual Center." + "`r`n vCenter Name : $vCenterFullName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
			$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		}
		Finally {
			# Disconnect from Virtual Center
			Disconnect-VIServer -Server $vc -Confirm:$false
		}
    }

}
#==================================================================================
#= End of Script Block That the Job will Run
#==================================================================================

#Start by setting up API object.
$api = New-Object -comObject 'MOM.ScriptAPI'

# Log Startup Message
$message = "Script Started for, " + $vCenterFullName
$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 


Try {

	$JobName = "DiscoverVirtualCenter-" + $vCenterFullName

	# Start The Job
	Start-Job -Name $JobName -ScriptBlock $DiscoverVirtualCenter -ArgumentList $vCenterFullName, $IpAddress, $UserName, $Password, $Debug | Out-Null

	# Wait For Job
	Wait-Job -Name $JobName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $JobName

	# Remove Job
	Remove-Job -Name $JobName

	# Create Discovery Data
	$DiscoveryData = $api.CreateDiscoveryData(0, $sourceId,  $managedEntityId)

	# Loop Through Results
	Foreach ($result in $Results) {
		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.Name -match "FullName")) {			
			# Save Full Name for Logging
			$instanceList += $isntanceList + $result.FullName + "`r`n"
			
			$instance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.VirtualCenter']$")
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $result.FullName)
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/ShortName$", $result.ShortName)
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/IPAddress$", $result.IpAddress)
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/ObjectType$", "VirtualCenter")
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/ProductFullName$", $result.ProductFullName)
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/ProductShortName$", $result.ProductShortName)
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/Version$", $result.Version)
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/Build$", $result.Build)
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/OsType$", $result.OsType)
			$DiscoveryData.AddInstance($instance)

			# Add Groups
			# Cluster Group
			$clustersGroup = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.VirtualCenter.ClustersGroup']$") 
			$clustersGroup.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $result.FullName)
			$clustersGroup.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.ClustersGroup']/Name$", "Clusters")
			$DiscoveryData.AddInstance($clustersGroup)

			# Hosts Group
			$hostsGroup = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.VirtualCenter.HostsGroup']$") 
			$hostsGroup.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $result.FullName)
			$hostsGroup.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.HostsGroup']/Name$", "Hosts")
			$DiscoveryData.AddInstance($hostsGroup)

			# Datastores Group
			$datastoresGroup = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.VirtualCenter.DatastoresGroup']$") 
			$datastoresGroup.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $result.FullName)
			$datastoresGroup.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.DatastoresGroup']/Name$", "Datastores")
			$DiscoveryData.AddInstance($datastoresGroup)

			# vm Group
			$vmGroup = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.VirtualCenter.VirtualMachinesGroup']$") 
			$vmGroup.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $result.FullName)
			$vmGroup.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.VirtualMachinesGroup']/Name$", "Virtual Machines")
			$DiscoveryData.AddInstance($vmGroup)

		}	
	}
	# Log Discovery Data if Debug Enabled
	if ($Debug -eq $true) { 
		$message = "Discovered :`r`n" + $instanceList
		$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_DISCOVERY_CREATED,$EVENT_LEVEL_INFO, $message) 
	} 
	$DiscoveryData

} Catch {
	$message = "Error Running ScriptBlock." + "`r`n vCenter Name : $vCenterFullName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
	$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
}
# Get End Time For Script
$EndTime = (GET-DATE)
$TimeTaken = NEW-TIMESPAN -Start $StartTime -End $EndTime
$Seconds = [math]::Round($TimeTaken.TotalSeconds, 2)
    
# Log Finished Message
$message = "Script Finished for, " + $vCenterFullName + ". Took $Seconds Seconds to Complete!"
$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ENDED,$EVENT_LEVEL_INFO, $message) 
