#==================================================================================
# Script: 	Discover-Clusters.ps1
# Date:		21/01/19
# Author: 	Andi Patrick
# Purpose:	Discovers Clusters in a Virtual Center
#==================================================================================

# Get the named parameters
Param(
	$sourceId, 
	$managedEntityId, 
    [string]$vCenterFullName, 
    [string]$UserName, 
    [string]$Password, 
    [string]$Debug 
)

# Get Start Time For Script
$StartTime = (GET-DATE)

#Constants used for event logging
$SCRIPT_NAME			= 'Discover-Clusters.ps1'
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
$DiscoverClusters = {
# Get the named parameters
	Param(
		[string]$vCenterFullName, 
		[string]$UserName, 
		[string]$Password, 
		[string]$Debug 
	)

	#Constants used for event logging
	$SCRIPT_NAME			= 'Discover-Clusters.ps1'
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
			
			# Get Cluster Views
			$clusterViews = Get-View -Server $vc -ViewType ClusterComputeResource -Property Name, Summary

			# Loop Through Each Cluster
			Foreach ($clusterView in $clusterViews){

				# Create Cluster Object
				$clusterObject = [PSCustomObject]@{
					vCenterFullName = $vCenterFullName
					Name = $clusterView.Name
					MoRef = $clusterView.MoRef.ToString()
					ObjectType = $clusterView.MoRef.Type
					TotalCpu = $clusterView.Summary.TotalCpu
					TotalMemory = [Math]::Round($clusterView.Summary.TotalMemory / 1024 / 1024 / 1024, 0)
					TotalHosts = $clusterView.Summary.NumHosts
					CpuCores = $clusterView.Summary.NumCpuCores
					CpuThreads = $clusterView.Summary.NumCpuThreads
					vMotionCount = $clusterView.Summary.NumVmotions
				}
				# Return it
				$clusterObject
			}
		} Catch {
			$message = "Error Getting Cluster Info from Virtual Center." + "`r`n vCenter Name : $vCenterFullName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
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

	$JobName = "DiscoverClusters-" + $vCenterFullName

	# Start The Job
	Start-Job -Name $JobName -ScriptBlock $DiscoverClusters -ArgumentList $vCenterFullName, $UserName, $Password, $Debug | Out-Null

	# Wait For Job
	Wait-Job -Name $JobName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $JobName

	# Remove Job
	Remove-Job -Name $JobName

	# Create Discovery Data Object
	$DiscoveryData = $api.CreateDiscoveryData(0, $sourceId,  $managedEntityId)

	# Loop Through Results
	Foreach ($result in $Results) {
		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.name -match "vCenterFullName")) {		
			$instanceList += "`r`n" + $result.Name
			# Create a Cluster Instance
			$instance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.Cluster']$")
			# Add Virtual Center Reference
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
			# Add Parent Group Reference
			$instance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.ClustersGroup']/Name$", "Clusters")
			# Add Display Name Property from System.Entity
			$instance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $result.Name)
			# Add Properties
			$instance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/Name$", $result.Name)
			$instance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/MoRef$", $result.MoRef)
			$instance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/ObjectType$", $result.ObjectType)
			$instance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/TotalCpu$", $result.TotalCpu)
			$instance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/TotalMemory$", $result.TotalMemory)
			$instance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/TotalHosts$", $result.TotalHosts)
			$instance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/CpuCores$", $result.CpuCores)
			$instance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/CpuThreads$", $result.CpuThreads)
			$instance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/vMotionCount$", $result.vMotionCount)


			$DiscoveryData.AddInstance($instance)
		}	
	}
	# Log Discovery Data if Debug Enabled
	if ($Debug -eq $true) { 
		$message = "Clusters Discovered on $vCenterFullName : `r`n" + $instanceList
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
