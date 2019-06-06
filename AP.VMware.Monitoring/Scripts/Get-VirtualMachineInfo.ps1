#==================================================================================
# Script: 	Get-VirtualMachineInfo.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets Virtual Machine Info from Virtual Center return all as Property Bags
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
$SCRIPT_NAME			= 'Get-VirtualMachineInfo.ps1'
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
$GetVirtualMachineInfo = {
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
	$SCRIPT_NAME			= 'Get-VirtualMachineInfo.ps1'
	$EVENT_LEVEL_ERROR 		= 1
	$EVENT_LEVEL_WARNING 	= 2
	$EVENT_LEVEL_INFO 		= 4

	$SCRIPT_STARTED				= 4701
	$SCRIPT_PROPERTYBAG_CREATED	= 4702
	$SCRIPT_EVENT				= 4703
	$SCRIPT_ENDED				= 4704
	$SCRIPT_ERROR				= 4705

	#==================================================================================
	# Sub:		Get-VMFolderName
	# Purpose:	Gets the Direct Parent Folder Name for a VM
	#==================================================================================
	function Get-VMFolderName
	{
		param($FullPath)

		$PathElements = $FullPath.Split("/")
		$RootElements = $PathElements[0].Split("]")
		$RootElements[$RootElements.Count - 1].Trim()	
	}
	
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

			# Get Service Instance and Performance Manager
			$si = Get-View -Server $vc serviceinstance
			$PerfMgr = Get-View -Server $vc -Id $si.Content.PerfManager

			#Create performance counter hashtable
			$pcTable = New-Object Hashtable
			$keyTable = New-Object Hashtable
			foreach($pC in $PerfMgr.PerfCounter){
				if($pC.Level -ne 99){
					if(!$pctable.containskey($pC.GroupInfo.Key + "." + $pC.NameInfo.Key + "." + $pC.RollupType)){
					$pctable.Add(($pC.GroupInfo.Key + "." + $pC.NameInfo.Key + "." + $pC.RollupType),$pC.Key)
					$keyTable.Add($pC.Key, $pC)
					}
				}
			}

			[String[]]$StatList = @("cpu.usage.average", "cpu.ready.summation", "mem.usage.average", "disk.usage.average", "net.usage.average")
			[String[]]$StatListNoNet = @("cpu.usage.average", "cpu.ready.summation", "mem.usage.average", "disk.usage.average")

			# Create Default Performance Query Spec Object
			$PQSpec = New-Object VMware.Vim.PerfQuerySpec   
			$PQSpec.Format = "normal"
			$PQSpec.IntervalId = 20
			$PQSpec.MaxSample = 16
			$PQSpec.MetricId = @()
			# Loop Through Stats we want to Gather
			Foreach($stat in $StatList) {
				# Create Performance Metric Object
				$PMId = New-Object VMware.Vim.PerfMetricId
				$PMId.counterId = $pcTable[$stat]
				$PMId.Instance =  ""
				$PQSpec.MetricId += $PMId										
			}

			# Create No Network Performance Query Spec Object (For VMs with No Connected ADapters)
			$PQSpecNoNet = New-Object VMware.Vim.PerfQuerySpec   
			$PQSpecNoNet.Format = "normal"
			$PQSpecNoNet.IntervalId = 20
			$PQSpecNoNet.MaxSample = 16
			$PQSpecNoNet.MetricId = @()
			# Loop Through Stats we want to Gather
			Foreach($stat in $StatListNoNet) {
				# Create Performance Metric Object
				$PMId = New-Object VMware.Vim.PerfMetricId
				$PMId.counterId = $pcTable[$stat]
				$PMId.Instance =  ""
				$PQSpecNoNet.MetricId += $PMId										
			}


			# Get List of VMs
			$vmList = Get-View -Server $vc -ViewType "VirtualMachine" -Filter @{"Config.Template"="false"} -Property Name, Guest, Summary.Config, Summary.Runtime, Summary.QuickStats

			Foreach ($vm in $vmList) {
				Try {

					# Reset Stats
					$CpuReady = 0
					$CpuUsageAvg = 0
					$CpuUsageMax = 0
					$MemUsageAvg = 0
					$MemUsageMax = 0
					$DiskUsage = 0
					$Netusage = 0

					# Get VM Name
					$VmName = $vm.Name

					# See if HostName Matches
					$HostName = $vm.Guest.HostName
					$HostNameMatches = "true"
					if ($HostName -ne $null) {
						$ShortHostName = $HostName.Split('.')[0]
						if ($ShortHostName -ne $vm.Name) { 
							$HostNameMatches = "false" 
						}
					}
			
					# See if Folder Matches
					$Folder = Get-VMFolderName($vm.Summary.Config.VmPathName)
					$FolderMatches = "true"
					if ($Folder -ne $vm.Name) {
						$FolderMatches = "false"
					}

					$PowerState = [string]$vm.Summary.Runtime.PowerState
					$PoweredOffDaysAgo = 255
					$PoweredOffBy = "Unknown"

					If ($PowerState -eq "poweredOff") {
						# Get Events
						$EventsLog = Get-VIEvent -Entity (Get-VIObjectByVIView -Server $vc -MoRef $vm.MoRef) | where{$_ -is [VMware.Vim.VmPoweredOffEvent] -or $_ -is [VMware.Vim.VmGuestShutdownEvent]} 
						# Are there Events
						If ($EventsLog.Count -ne 0) {
							$lastPO = $EventsLog | Sort-Object -Property CreatedTime -Descending | Select -First 1			
							$PoweredOffDaysAgo = ((Get-Date) - $lastPO.CreatedTime).TotalDays
							$PoweredOffBy = $lastPO.UserName
						}

					} else {

						# VM Is Powered On so we can Gather Stats		
						Try {
							# Set Entity to This VM
							$PQSpec.entity = $vm.MoRef
							# Get Stats
							$Stats = $PerfMgr.QueryPerf($PQSpec)
							

							if($Stats[0].Value -ne $null) {

								# Get CPU Ready
								$CpuReady = [Math]::Round(((($Stats.Value | where {$_.Id.CounterId -eq $pcTable["cpu.ready.summation"]} ).Value | Measure-Object -Average).Average / 20000) * 100, 2)

								$CpuUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["cpu.usage.average"]}).Value | Measure-Object -Average -Maximum
								$CpuUsageAvg = [Math]::Round([double]($CpuUsage.Average /100), 2)
								$CpuUsageMax = [Math]::Round([double]($CpuUsage.Maximum /100), 2)
								# Get Memory Usage Average/Maximum
								$MemUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["mem.usage.average"]}).Value | Measure-Object -Average -Maximum
								$MemUsageAvg = [Math]::Round([double]($MemUsage.Average /100), 2)
								$MemUsageMax = [Math]::Round([double]($MemUsage.Maximum /100), 2)

								# Get disk Usage Average/Maximum
								$DiskUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["disk.usage.average"]}).Value | Measure-Object -Average -Maximum

								# Get Net Usage Average/Maximum
								$NetUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["net.usage.average"]}).Value | Measure-Object -Average -Maximum
							}
						} Catch {
							# Set Entity to This VM
							$PQSpecNoNet.entity = $vm.MoRef
							# Get Stats
							$Stats = $PerfMgr.QueryPerf($PQSpecNoNet)
							

							if($Stats[0].Value -ne $null) {

								# Get CPU Ready
								$CpuReady = [Math]::Round(((($Stats.Value | where {$_.Id.CounterId -eq $pcTable["cpu.ready.summation"]} ).Value | Measure-Object -Average).Average / 20000) * 100, 2)

								$CpuUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["cpu.usage.average"]}).Value | Measure-Object -Average -Maximum
								$CpuUsageAvg = [Math]::Round([double]($CpuUsage.Average /100), 2)
								$CpuUsageMax = [Math]::Round([double]($CpuUsage.Maximum /100), 2)
								# Get Memory Usage Average/Maximum
								$MemUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["mem.usage.average"]}).Value | Measure-Object -Average -Maximum
								$MemUsageAvg = [Math]::Round([double]($MemUsage.Average /100), 2)
								$MemUsageMax = [Math]::Round([double]($MemUsage.Maximum /100), 2)

								# Get disk Usage Average/Maximum
								$DiskUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["disk.usage.average"]}).Value | Measure-Object -Average -Maximum
							}
							
						}

					}	

					# Create VirtualMachine Object
					$vmObject = [PSCustomObject]@{
						VirtualMachineKey = [string]$vm.MoRef.ToString()
						VirtualMachineName = [string]$VmName
						PowerState = $PowerState
						PoweredOffBy = $PoweredOffBy
						PoweredOffTime = $PoweredOffTime
						PoweredOffDaysAgo = $PoweredOffDaysAgo
						vmToolsState = [string]$vm.Guest.ToolsRunningStatus
						ConsolidationNeeded = [string]$vm.Summary.Runtime.ConsolidationNeeded.ToString()
						HostNameMatches = [string]$HostNameMatches
						FolderMatches = [string]$HostNameMatches
						SwapMemoryUsage = [int]$vm.Summary.QuickStats.SwappedMemory
						BalloonMemoryUsage = [int]$vm.Summary.QuickStats.BalloonedMemory
						CpuReady = [double]$CpuReady
						CpuUsageAvg = [double]$CpuUsageAvg
						CpuUsagePeak = [double]$CpuUsageMax
						MemUsageAvg = [double]$MemUsageAvg
						MemUsagePeak = [double]$MemUsageMax
						DiskUsageAvg = [int]$DiskUsage.Average 
						DiskUsagePeak = [int]$DiskUsage.Maximum
						NetUsageAvg = [int]$NetUsage.Average 
						NetUsagePeak = [int]$NetUsage.Maximum 
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
if ($Debug -eq $true) { 
	$message = "Script Started for, " + $vCenterName
	$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 
}

Try {
	$JobName = 'vmInfo' + $vCenterName

	# Start The Job
	Start-Job -Name $JobName -ScriptBlock $GetVirtualMachineInfo -ArgumentList $vCenterName, $UserName, $Password, $Debug | Out-Null

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
			$bag.AddValue("PowerState", $result.PowerState)
			$bag.AddValue("PoweredOffBy", $result.PoweredOffBy)
			$bag.AddValue("PoweredOffTime", $result.PoweredOffTime)
			$bag.AddValue("PoweredOffDaysAgo", $result.PoweredOffDaysAgo)
			$bag.AddValue("vmToolsState", $result.vmToolsState)
			$bag.AddValue("ConsolidationNeeded", $result.ConsolidationNeeded)
			$bag.AddValue("HostNameMatches", $result.HostNameMatches)
			$bag.AddValue("FolderMatches", $result.FolderMatches)
			$bag.AddValue("SwapMemoryUsage", $result.SwapMemoryUsage)
			$bag.AddValue("BalloonMemoryUsage", $result.BalloonMemoryUsage)
			$bag.AddValue("CpuReady", $result.CpuReady)
			$bag.AddValue("CpuUsageAvg", $result.CpuUsageAvg)
			$bag.AddValue("CpuUsagePeak", $result.CpuUsagePeak)
			$bag.AddValue("MemUsageAvg", $result.MemUsageAvg)
			$bag.AddValue("MemUsagePeak", $result.MemUsagePeak)
			$bag.AddValue("DiskUsageAvg", $result.DiskUsageAvg)
			$bag.AddValue("DiskUsagePeak", $result.DiskUsagePeak)
			$bag.AddValue("NetUsageAvg", $result.NetUsageAvg)
			$bag.AddValue("NetUsagePeak", $result.NetUsagePeak)

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
if ($Debug -eq $true) { 
	$message = "Script Finished for, " + $vCenterName + ". Took $Seconds Seconds to Complete!"
	$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ENDED,$EVENT_LEVEL_INFO, $message) 
}
