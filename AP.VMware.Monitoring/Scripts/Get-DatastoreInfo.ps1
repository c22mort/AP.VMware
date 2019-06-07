#==================================================================================
# Script: 	Get-DatastoreInfo.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets info from Datastore return all as Property Bags
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
$SCRIPT_NAME			= 'Get-DatastoreInfo.ps1'
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
$GetDatastoreInfo = {
    Param(
        [string]$vCenterName, 
        [string]$UserName, 
        [string]$Password, 
        [string]$Debug
    )   

    #Constants used for event logging
    $SCRIPT_NAME			= 'Get-Datastorehealth.ps1'
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
	    $message = "Error Importing PowerCLI Mudules" + "`r`n" + $_
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

   			# Report Progress.
            if ($Debug -eq $true) { 
    			[string] $message = "`r`nGetting Statistics for Datastores, this can take some time depending on number of datastores"
                $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_PROPERTYBAG_CREATED,$EVENT_LEVEL_INFO, $message) 
            } 

			# Get Stats for Hosts
			foreach ($vmHost in Get-VMHost -Server $vc) {
				if ($vmHost.ConnectionState -ne "Connected") {continue}
				$statistic_data += (Get-Stat -Entity $vmhost -Stat 'datastore.numberreadaveraged.average','datastore.numberwriteaveraged.average','datastore.totalreadlatency.average', 'datastore.totalwritelatency.average' -Realtime -MaxSamples 16 )
			}

		    # Get Datastore Views
		    $DatastoreViews = Get-View -Server $vc -ViewType Datastore -Property Summary, Name
		    $HostViews = Get-View -Server $vc -ViewType HostSystem -Property Config.CacheConfigurationInfo, Datastore
		    $CacheDiskList = New-Object System.Collections.ArrayList

		    # Get Cache Disks
		    foreach ($HostView in $HostViews){
			    if (-not $HostView.Config.CacheConfigurationInfo) {continue}
			    [string]$CacheDisk = $HostView.Config.CacheConfigurationInfo.Key.Value.ToString()
			    if (-not $CacheDiskList.Contains($CacheDisk)) {
				    $CacheDiskList.Add($CacheDisk) > $null
			    }
		    }

		    # Loop through Datastore Views
		    foreach ($DatastoreView in $DatastoreViews) {
                Try {

			        # If this is a Cache Disk Then Set Everything to 0 (Cache Disks are normally Full so we won't be measuring Capacity)
			        if ($CacheDiskList.Contains($DatastoreView.MoRef.Value.ToString())) {
				        $Capacity = 0;
				        $FreeSpace = 0;
				        $Percentage = 0;
				        # Ignore VMware Disk Space Check for Cache Disks
				        If ($AlarmList -eq "Datastore usage on disk") {
					        $OverallStatus = "green"
					        $AlarmList = ""
				        }
			        } else {
				        $Capacity = [Math]::Round($DatastoreView.Summary.Capacity / 1024 / 1024 / 1024, 2)
				        $FreeSpace = [Math]::Round($DatastoreView.Summary.FreeSpace / 1024 / 1024 / 1024, 2)
				        $FreePercentage = [Math]::Round(($FreeSpace / $Capacity) * 100, 2)		
			        }
   					# Report Progress.
                    if ($Debug -eq $true) { 
    					[string] $message = "`r`nGetting Health Properties for Datastore " + $DatastoreView.Name
                        $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_PROPERTYBAG_CREATED,$EVENT_LEVEL_INFO, $message) 
                    } 


					# Reset Counters
					$ReadIOPs = 0
					$WriteIOPs = 0
					$TotalIOPs = 0
					$ReadLatency = 0
					$ReadLatencyCounter = 0
					$WriteLatency = 0
					$WriteLatencyCounter = 0
					# Get Stats, First We Have to Get Hosts
					foreach ($stat in $statistic_data) {
						if ($DatastoreView.Summary.Url.Tostring().Contains($stat.Instance.ToString())) {
							If ($stat.MetricId.ToString() -eq "datastore.numberreadaveraged.average") {
								$ReadIOPs += $stat.Value
							}
							If ($stat.MetricId.ToString() -eq "datastore.numberwriteaveraged.average") {
								$WriteIOPs += $stat.Value
							}
							If ($stat.MetricId.ToString() -eq "datastore.totalreadlatency.average") {
								$ReadLatencyCounter++
								$ReadLatency += $stat.Value
							}
							If ($stat.MetricId.ToString() -eq "datastore.totalwritelatency.average") {
								$WriteLatencyCounter++
								$WriteLatency += $stat.Value
							}

						}
					}	
					
					$TotalIOPs = $ReadIOPs + $WriteIOPs
					If ($ReadLatencyCounter -ne 0) {
						$ReadLatencyAvg = $ReadLatency / $ReadLatencyCounter				
					}
					If ($WriteLatencyCounter -ne 0) {
						$WriteLatencyAvg = $WriteLatency / $WriteLatencyCounter				
					}

				    # Create Datastore Object
				    $dsObject = [PSCustomObject]@{
						DatastoreKey = [string]$DatastoreView.MoRef.ToString()
						DatastoreName = [string]$DatastoreView.Name
						Accessible = [string]$DatastoreView.Summary.Accessible
                        Capacity = [double]$Capacity
                        FreeSpace = [double]$FreeSpace
                        UsedSpace = [double]($Capacity - $FreeSpace)
                        FreePercentage = [double]$FreePercentage
						UsedPercentage = [Math]::Round(($Capacity - $FreeSpace) / $Capacity) * 100, 2)		
						ReadIOPs = [Math]::Round([double]$ReadIOPs,2)
						WriteIOPs = [Math]::Round([double]$WriteIOPs,2)
						TotalIOPs = [Math]::Round([double]$TotalIOPs,2)
						ReadLatency = [Math]::Round([double]$ReadLatencyAvg,2)
						WriteLatency = [Math]::Round([double]$WriteLatencyAvg,2)
                    }
				    # Return it
				    $dsObject

                } Catch {
				    $message = "Error Getting Info from Datastore." + "`r`n vCenter Name : $vCenterName" + "`r`nDatastore Name : " + $DatastoreView.Name + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
				    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
				    Continue
                }

            }

		} Catch {
			$message = "Error Getting VMs and Datastores from Virtual Center." + "`r`n vCenter Name : $vCenterName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
			$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		}
		Finally {
			# Disconnect from Virtual Center
			Disconnect-VIServer -Server $vc -Confirm:$false
		}
    }
} ### End of Script Block

Try {
	$JobName = "GetDatastoreInfo" + $vCenterName

	# Start The Job
	Start-Job -Name $JobName -ScriptBlock $GetDatastoreInfo -ArgumentList $vCenterName, $UserName, $Password, $Debug | Out-Null

	# Wait For Job
	Wait-Job -Name $JobName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $JobName

	# Remove Job
	Remove-Job -Name $JobName

	# Loop Through Results
	Foreach ($result in $Results) {

		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.name -match "DatastoreKey")) {			
            $bag = $api.CreatePropertyBag()
			$bag.AddValue("DatastoreKey", $result.DatastoreKey)
			$bag.AddValue("DatastoreName", $result.DatastoreName)
			$bag.AddValue("Accessible", $result.Accessible)
			$bag.AddValue("Capacity", $result.Capacity)
			$bag.AddValue("FreeSpace", $result.FreeSpace)
			$bag.AddValue("UsedSpace", $result.UsedSpace)
			$bag.AddValue("FreePercentage", $result.FreePercentage)
			$bag.AddValue("UsedPercentage", $result.UsedPercentage)
			$bag.AddValue("ReadIOPs", $result.ReadIOPs)
			$bag.AddValue("WriteIOPs", $result.WriteIOPs)
			$bag.AddValue("TotalIOPs", $result.TotalIOPs)
			$bag.AddValue("ReadLatency", $result.ReadLatency)
			$bag.AddValue("WriteLatency", $result.WriteLatency)
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
