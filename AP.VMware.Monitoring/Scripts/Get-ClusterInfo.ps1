#==================================================================================
# Script: 	Get-ClusterInfo.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets info from Cluster return all as Property Bags
#==================================================================================

# Get the named parameters
Param(
    [string]$vCenterName, 
    [string]$UserName, 
    [string]$Password, 
    [string]$Debug 
)

# Get Start Time For Script
$StartTime = (GET-DATE)

#Constants used for event logging
$SCRIPT_NAME			= 'Get-ClusterInfo.ps1'
$EVENT_LEVEL_ERROR 		= 1
$EVENT_LEVEL_WARNING 	= 2
$EVENT_LEVEL_INFO 		= 4

$SCRIPT_STARTED				= 4701
$SCRIPT_PROPERTYBAG_CREATED	= 4702
$SCRIPT_EVENT				= 4703
$SCRIPT_ENDED				= 4704
$SCRIPT_ERROR				= 4705

#Start by setting up API object.
$api = New-Object -comObject 'MOM.ScriptAPI'

# Log Startup Message
if ($Debug -eq $true) { 
    $message = "Script Started for, " + $vCenterName
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 
} 

#==================================================================================
#= Declare Our Script Block That the Job will Run
#==================================================================================
$GetClusterInfo = {
    Param(
        [string]$vCenterName, 
        [string]$UserName, 
        [string]$Password, 
        [string]$Debug
    )   

    #Constants used for event logging
    $SCRIPT_NAME			= 'Get-ClusterInfo.ps1'
    $EVENT_LEVEL_ERROR 		= 1
    $EVENT_LEVEL_WARNING 	= 2
    $EVENT_LEVEL_INFO 		= 4

    $SCRIPT_STARTED				= 4701
    $SCRIPT_PROPERTYBAG_CREATED	= 4702
    $SCRIPT_EVENT				= 4703
    $SCRIPT_ENDED				= 4704
    $SCRIPT_ERROR				= 4705

    #Start by setting up API object.
    $api = New-Object -comObject 'MOM.ScriptAPI'

    #
    # Import PowerCLI Modules
    Try {
	    Import-Module VMware.VimAutomation.Core
    } Catch {
	    $message = "Error Importing PowerCLI Modules" + "`r`n" + $_
	    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
	    Exit
    }

    #
    # Connect to Virtual Centerr
    Try {
	    $vc = Connect-VIServer $vCenterName -User $UserName -Password $Password -Force:$true -NotDefault	
    } Catch {
		$message = "Error Connecting to Virtual Center" + "`r`n" + $_
		$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		Exit		
    }

    If ($vc) {
		# At this point Modules Should be loaded and vCenter Connected
		Try {
		    # Get List of VMs (Layout Only)
		    $ClusterList = Get-View -Server $vc -ViewType ClusterComputeResource -Property Name, Configuration

			# Loop Through Clusters
			Foreach ($Cluster in $ClusterList) {

				# Get Cluster DataStores
				#$Cluster.Configuration.DrsConfig.Enabled
				#$Cluster.Configuration.DasConfig.Enabled

			    # Create Datastore Object
			    $dsObject = [PSCustomObject]@{
					ClusterName = [string]$Cluster.Name
					ClusterKey = [string]$Cluster.MoRef.ToString()
					ClusterHaEnabled = $Cluster.Configuration.DasConfig.Enabled
					ClusterDrsEnabled = $Cluster.Configuration.DrsConfig.Enabled
				}
				$dsObject
				
			}

		} Catch {
			$message = "Error Getting Clusters from Virtual Center." + "`r`n vCenter Name : $vCenterName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
			$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		}
		Finally {
			# Disconnect from Virtual Center
			Disconnect-VIServer -Server $vc -Confirm:$false
		}
    }
}

Try {
	$JobName = "GetClusterInfo" + $vCenterName

	# Start The Job
	Start-Job -Name $JobName -ScriptBlock $GetClusterInfo -ArgumentList $vCenterName, $UserName, $Password, $Debug | Out-Null

	# Wait For Job
	Wait-Job -Name $JobName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $JobName

	# Remove Job
	Remove-Job -Name $JobName

	# Loop Through Results
	Foreach ($result in $Results) {
		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.name -match "ClusterKey")) {			
            $bag = $api.CreatePropertyBag()
			$bag.AddValue("ClusterKey", $result.ClusterKey)
			$bag.AddValue("ClusterName", $result.ClusterName)
			$bag.AddValue("ClusterHaEnabled", $result.ClusterHaEnabled)
			$bag.AddValue("ClusterDrsEnabled", $result.ClusterDrsEnabled)
            #$api.Return($bag)
			$bag	
		}	
	}

} Catch {
	$message = "Error Running ScriptBlock." + "`r`n vCenter Name : $vCenterName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
	$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
}

# Log Finished Message
if ($Debug -eq $true) {
	# Get End Time For Script
	$EndTime = (GET-DATE)
	$TimeTaken = NEW-TIMESPAN -Start $StartTime -End $EndTime
	$Seconds = [math]::Round($TimeTaken.TotalSeconds, 2)
	# Display Message
    $message = "Script Finished for, " + $vCenterName + ". Took $Seconds Seconds to Complete!"
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ENDED,$EVENT_LEVEL_INFO, $message) 
}
