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

			[String[]]$StatList = @("cpu.usage.average", "cpu.ready.summation", "mem.usage.average", "disk.usage.average", "net.usage.average", "disk.maxTotalLatency.latest")
			[String[]]$StatListNoNet = @("cpu.usage.average", "cpu.ready.summation", "mem.usage.average", "disk.usage.average", "disk.maxTotalLatency.latest")

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
					$CpuUsagePeak = 0
					$MemUsageAvg = 0
					$MemUsagePeak = 0
					$DiskUsage = 0
					$NetUsage = 0
					$DiskLatency = 0

					# Get VM Name
					$VmName = $vm.Name

					# Get ShortHostName
					$HostName = $vm.Guest.HostName
					if ($HostName -ne $null) {
						$HostName = $HostName.Split('.')[0]
					}
			
					# Get Folder Matches
					$FolderName = Get-VMFolderName($vm.Summary.Config.VmPathName)

					# Get Power State
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
							$PoweredOffTime = $lastPO.CreatedTime
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
								$CpuUsagePeak = [Math]::Round([double]($CpuUsage.Maximum /100), 2)
								# Get Memory Usage Average/Maximum
								$MemUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["mem.usage.average"]}).Value | Measure-Object -Average -Maximum
								$MemUsageAvg = [Math]::Round([double]($MemUsage.Average /100), 2)
								$MemUsagePeak = [Math]::Round([double]($MemUsage.Maximum /100), 2)

								# Get disk Usage Average/Maximum
								$DiskUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["disk.usage.average"]}).Value | Measure-Object -Average -Maximum

								# Get Net Usage Average/Maximum
								$NetUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["net.usage.average"]}).Value | Measure-Object -Average -Maximum

								# Get Disk Latency Average/Maximum
								$DiskLatency = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["disk.maxTotalLatency.latest"]}).Value | Measure-Object -Average -Maximum
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

								# Get Disk Latency Average/Maximum
								$DiskLatency = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["disk.maxTotalLatency.latest"]}).Value | Measure-Object -Average -Maximum

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
						HostName = [string]$HostName
						FolderName = [string]$FolderName
						SwapMemoryUsage = [int]$vm.Summary.QuickStats.SwappedMemory
						BalloonMemoryUsage = [int]$vm.Summary.QuickStats.BalloonedMemory
						CpuReady = [double]$CpuReady
						CpuUsageAvg = [double]$CpuUsageAvg
						CpuUsagePeak = [double]$CpuUsagePeak
						MemUsageAvg = [double]$MemUsageAvg
						MemUsagePeak = [double]$MemUsagePeak
						DiskLatencyAvg = [double]$DiskLatency.Average 
						DiskLatencyPeak = [double]$DiskLatency.Maximum
						# Disk Usage Converted from KB/s to B/s (For SquaredUp)
						DiskUsageAvg = [double]$DiskUsage.Average * 1000 
						DiskUsagePeak = [double]$DiskUsage.Maximum * 1000
						# Disk Usage Converted from KB/s to bps (For SquaredUp)
						NetUsageAvg = [double]$NetUsage.Average * 8000
						NetUsagePeak = [double]$NetUsage.Maximum * 8000
					}
					# Return Object
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