#==================================================================================
# Script: 	Get-VirtualMachineDiskSpace.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets Orphaned Virtual Machines from Datastore return all as Property Bags
#==================================================================================

# Get the named parameters
Param(
    [string]$vCenterName, 
    [string]$UserName, 
    [string]$Password, 
    [string]$Debug,
	[double]$WarningThresholdPercent, 
	[double]$WarningThresholdMb, 
	[double]$CriticalThresholdPercent, 
	[double]$CriticalThresholdMb
)

# Get Start Time For Script
$StartTime = (GET-DATE)

#Constants used for event logging
$SCRIPT_NAME			= 'Get-VirtualMachineDiskSpace.ps1'
$EVENT_LEVEL_ERROR 		= 1
$EVENT_LEVEL_WARNING 	= 2
$EVENT_LEVEL_INFO 		= 4

$SCRIPT_STARTED				= 4701
$SCRIPT_PROPERTYBAG_CREATED	= 4702
$SCRIPT_EVENT				= 4703
$SCRIPT_ENDED				= 4704
$SCRIPT_ERROR				= 4705

#==================================================================================
#= Declare Our Script Block That the Job will Run
#==================================================================================
$GetVirtualMachineDiskSpace = {
    Param(
        [string]$vCenterName, 
        [string]$UserName, 
        [string]$Password, 
        [string]$Debug,
		[double]$WarningThresholdPercent, 
		[double]$WarningThresholdMb, 
		[double]$CriticalThresholdPercent, 
		[double]$CriticalThresholdMb
    )   

    #Constants used for event logging
    $SCRIPT_NAME			= 'Get-VirtualMachineDiskSpace.ps1'
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

			# Get View of VMs
			$vmlist = Get-View -Server $vc -ViewType VirtualMachine -Property Name,Guest
			# Loop through VMs
			foreach ($vm in $vmlist) {
				Try {
					# Chack if there are Guest Disks
					if ($vm.Guest.Disk.Count -gt 0) {
					
						# Loop Through Guest Disks
						foreach ($disk in $vm.Guest.Disk) {
							# Get Capacity			
							$PercentageFree = [Math]::Round(($disk.FreeSpace / $disk.Capacity) * 100, 2)
							$SpaceFreeMb = [Math]::Round($disk.FreeSpace / 1024 / 1024 , 2)

							$DiskHealth = "Okay"
							if ($PercentageFree -lt $CriticalThresholdPercent) {
								if ($SpaceFreeMb -lt $CriticalThresholdMb) {
									$DiskHealth = "Critical"					
								}
							} else {
								if ($PercentageFree -lt $WarningThresholdPercent) {
									if ($SpaceFreeMb -lt $WarningThresholdMb) {
										$DiskHealth = "Warning"					
									}
								}
							}
							#Create a property bag.
		                    If ($Debug -eq $true) { 
								[string] $message = "Getting Data for : " + $vm.MoRef + "`r`nDisk : " + $disk.DiskPath + "`r`nPercentageFree : " + $PercentageFree+ "`r`nSpaceFree (Gb) : " + $SpaceFreeMb
			                    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_PROPERTYBAG_CREATED,$EVENT_LEVEL_INFO, $message) 
							}

						    # Create Datastore Object
							$diskObject = [PSCustomObject]@{
								VirtualMachineName = [string]$vm.Name
								VirtualMachineKey = [string]$vm.MoRef.ToString()
								DiskPath = [string]$disk.DiskPath
								DiskHealth = [string]$DiskHealth
								PercentageFree = $PercentageFree
								SpaceFreeMb = $SpaceFreeMb
							}
							# Return it
							$diskObject

						}

					
					}

				} Catch {
				    $message = "Error Getting Info from VM Disk." + "`r`n vCenter Name : $vCenterName" + "`r`nVirtual Machine : " + $vm.Name + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
				    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
					Continue
				}
			}
	

		} Catch {
			$message = "Error Getting VMs and Disks from Virtual Center." + "`r`n vCenter Name : $vCenterName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
			$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		}
		Finally {
			# Disconnect from Virtual Center
			Disconnect-VIServer -Server $vc -Confirm:$false
		}
    }
} ### End of Script Block

#Start by setting up API object.
$api = New-Object -comObject 'MOM.ScriptAPI'

# Log Startup Message
if ($Debug -eq $true) { 
    $message = "Script Started for, " + $vCenterName
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 
} 

Try {

	$JobName = "DiskSpace-" + $vCenterName

	# Start The Job
	Start-Job -Name $JobName -ScriptBlock $GetVirtualMachineDiskSpace -ArgumentList $vCenterName, $UserName, $Password, $Debug, $WarningThresholdPercent, $WarningThresholdMb, $CriticalThresholdPercent, $CriticalThresholdMb | Out-Null

	# Wait For Job
	Wait-Job -Name $JobName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $JobName

	# Remove Job
	Remove-Job -Name $JobName

	# Loop Through Results
	Foreach ($result in $Results) {

		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.name -match "VirtualMachineKey")) {
			$bag = $api.CreatePropertyBag()
			$bag.AddValue("VirtualMachineName", $result.VirtualMachineName)
			$bag.AddValue("VirtualMachineKey", $result.VirtualMachineKey)
			$bag.AddValue("DiskPath", $result.DiskPath)
			$bag.AddValue("DiskHealth", $result.DiskHealth)
			$bag.AddValue("PercentageFree", $result.PercentageFree)
			$bag.AddValue("SpaceFreeMb", $result.SpaceFreeMb)
			#$api.Return($bag)
			$bag	
		}	
	}

} Catch {
	$message = "Error Running ScriptBlock." + "`r`n vCenter Name : $vCenterName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
	$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
}

# Get End Time For Script
$EndTime = (GET-DATE)
$TimeTaken = NEW-TIMESPAN -Start $StartTime -End $EndTime
$Seconds = [math]::Round($TimeTaken.TotalSeconds, 2)
    
# Log Finished Message
if ($Debug -eq $true) {
    $message = "Script Finished for, " + $vCenterName + ". Took $Seconds Seconds to Complete!"
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ENDED,$EVENT_LEVEL_INFO, $message) 
}