#==================================================================================
# Script: 	Get-VirtualMachineBackupInfo.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets Virtual Machine Backup Info from Virtual Center return all as Property Bags
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
$SCRIPT_NAME			= 'Get-VirtualMachineBackupInfo.ps1'
$EVENT_LEVEL_ERROR 		= 1
$EVENT_LEVEL_WARNING 	= 2
$EVENT_LEVEL_INFO 		= 4

$SCRIPT_STARTED				= 4711
$SCRIPT_PROPERTYBAG_CREATED	= 4712
$SCRIPT_EVENT				= 4713
$SCRIPT_ENDED				= 4714
$SCRIPT_ERROR				= 4715

#==================================================================================
#= Declare Our Script Block That the Job will Run
#==================================================================================
$GetVirtualMachineBackupInfo = {
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
	$SCRIPT_NAME			= 'Get-VirtualMachineBackups.ps1'
	$EVENT_LEVEL_ERROR 		= 1
	$EVENT_LEVEL_WARNING 	= 2
	$EVENT_LEVEL_INFO 		= 4

	$SCRIPT_STARTED				= 4711
	$SCRIPT_PROPERTYBAG_CREATED	= 4712
	$SCRIPT_EVENT				= 4713
	$SCRIPT_ENDED				= 4714
	$SCRIPT_ERROR				= 4715

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

			
			# Get List of VMs
			$vmList = Get-View -Server $vc -ViewType "VirtualMachine" -Filter @{"Config.Template"="false"} -Property Name, AvailableField, CustomValue

			Foreach ($vm in $vmList) {
				Try {

					# Get VM Name
					$VmName = $vm.Name

					
					# Get Last Backup Custom Value
					$LastBackupKey = $vm.AvailableField | where {$_.Name -eq "Last Backup"} | Select -ExpandProperty Key
					If ($LastBackupKey -eq $null) { 
						$LastBackupDate = $null
						$LastBackupDaysAgo = 255
						$LastBackup = "No Last Backup Field"
					} else {
						$LastBackup = ($vm.CustomValue | where {$_.Key -eq $LastBackupKey}).Value
						If ($LastBackup -eq $null) {
							$LastBackupDate = $null
							$LastBackupDaysAgo = 255
							$LastBackup = "Last Backup Field is Blank"
						} else {
							# Try Converting to Date Time
							Try {
								[datetime]$LastBackupDate = $LastBackup
								$LastBackupDaysAgo = ((Get-Date) - $LastBackupDate).Days
							} Catch {
								# Not a Date Time So See What it Is
								$LastBackupDate = $null
								$LastBackupDaysAgo = 0
							}											
						}
					}

					# Create VirtualMachine Object
					$vmObject = [PSCustomObject]@{
						VirtualMachineKey = [string]$vm.MoRef.ToString()
						VirtualMachineName = [string]$VmName
						LastBackupDate = $LastBackupDate
						LastBackupDaysAgo = $LastBackupDaysAgo
						Comment = $LastBackup
					}

					$vmObject
					
				} Catch {
					$message = "Error Getting Info from VM." + "`r`n vCenter Name : $vCenterName" + "`r`nVirtual Machine : " + $vm.Name + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
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

#Start by setting up API object.
$api = New-Object -comObject 'MOM.ScriptAPI'

# Log Startup Message
$message = "Script Started for, " + $vCenterName
$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 

Try {
	$JobName = 'vmBackupInfo' + $vCenterName

	# Start The Job
	Start-Job -Name $JobName -ScriptBlock $GetVirtualMachineBackupInfo -ArgumentList $vCenterName, $UserName, $Password, $Debug | Out-Null

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
			$bag.AddValue("LastBackupDate", $result.LastBackupDate)
			$bag.AddValue("LastBackupDaysAgo", $result.LastBackupDaysAgo)
			$bag.AddValue("Comment", $result.Comment)

			#$api.Return($bag)
			$bag	

			# Add to reporting List
			$instanceList += "`r`n" + $result.VirtualMachineName
		}	
	}

	# Log Data if Debug Enabled
	if ($Debug -eq $true) { 
		$message = "Virtual Machine Property Bags Created on $vCenterFullName : `r`n" + $instanceList
		$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_PROPERTYBAG_CREATED,$EVENT_LEVEL_INFO, $message) 
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
$message = "Script Finished for, " + $vCenterName + ". Took $Seconds Seconds to Complete!"
$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ENDED,$EVENT_LEVEL_INFO, $message) 
