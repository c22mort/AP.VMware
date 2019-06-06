    Param(
        [string]$vCenterName, 
        [string]$UserName, 
        [string]$Password, 
        [string]$Debug
    )   

    #Constants used for event logging
    $SCRIPT_NAME			= 'Get-HostInfo.ps1'
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
    # Connect to Virtual Center
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

			# Get List of Hosts
			$HostViews = Get-View -Server $vc -ViewType HostSystem -Property Name, Summary, Hardware
			Foreach ($HostView in $HostViews) {

				# Get Basic Health Properties
				$HostInMaintenance = $HostView.Summary.Runtime.InMaintenanceMode
	
				# Get Host RAM Stats
				$HostRamUsage = $HostView.Summary.QuickStats.OverallMemoryUsage
				$HostTotalRam = [Math]::Round($HostView.Hardware.MemorySize / 1024 / 1024, 2)
				$HostTotalRamPercent = [Math]::Round(($HostRamUsage / $HostTotalRam) * 100, 2)

				# Get Host CPU Stats
				$HostNumPhysicalCores = $HostView.Hardware.CpuInfo.NumCpuCores
				$HostNumPhysicalThreads = $HostView.Summary.Hardware.NumCpuThreads
				$HostCpuUsage = $HostView.Summary.QuickStats.OverallCpuUsage
				$HostTotalCpu = $HostNumPhysicalCores * ($HostView.Hardware.CpuInfo.Hz / 1000 / 1000)
				$HostTotalCpuPercent = [Math]::Round(($HostCpuUsage / $HostTotalCpu) * 100, 2)

				# Get VMs
				$HostKey = $HostView.MoRef.ToString()
				$VmViews = Get-View -Server $vc -ViewType VirtualMachine -Property Config.Hardware, Summary.QuickStats  -Filter @{'Runtime.Host' = $HostView.MoRef.Value}
				$HostTotalVirtualCPU = 0
				$HostTotalVirtualRAM = 0
				$HostSwapUsage = 0
				$HostBallooning = 0
				Foreach ($vmv in $VmViews) {
					# Get CPU and Memory Count
					$HostTotalVirtualCPU += $vmv.Config.Hardware.NumCPU
					$HostTotalVirtualRAM += $vmv.Config.Hardware.MemoryMB
					$HostSwapUsage += $vmv.Summary.QuickStats.SwappedMemory
					$HostBallooning += $vmv.Summary.QuickStats.BalloonedMemory
				}

				# Check vCPU Over Commit
				$vCpuPhysicalCpuRatio = $HostTotalVirtualCPU / $HostNumPhysicalThreads


				# Get Stats
				# Set Entity to This VM
				$PQSpec.entity = $HostView.MoRef
				# Get Stats
				$Stats = $PerfMgr.QueryPerf($PQSpec)
				If ($Stats[0].Value -ne $null) {

					# Get CPU Ready
					$CpuReady = [Math]::Round(((($Stats.Value | where {$_.Id.CounterId -eq $pcTable["cpu.ready.summation"]} ).Value | Measure-Object -Average).Average / 20000) * 100, 2)

					# Get CPU Usage Average/Maximum
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

			    # Create Host Object
				$hostObject = [PSCustomObject]@{
					HostKey = [string]$HostView.MoRef.ToString()
					HostName = [string]$HostView.Name
                    HostInMaintenance = [string]$HostInMaintenance.ToString()
					HostTotalRamPercent = [double]$HostTotalRamPercent
					HostTotalCpuPercent = [double]$HostTotalCpuPercent
					HostNumPhysicalCores = [int]$HostNumPhysicalCores
					HostNumPhysicalThreads = [int]$HostNumPhysicalThreads
					HostTotalVirtualCPU = [int]$HostTotalVirtualCPU
					HostTotalVirtualRAM = [int]$HostTotalVirtualRAM
					HostvCpuPhysicalCpuRatio = [double][Math]::Round($vCpuPhysicalCpuRatio, 2)
					HostSwapUsage = [double]$HostSwapUsage
					HostBallooning = [double]$HostBallooning
					CpuReady = [double]$CpuReady
					CpuUsageAvg = [double]$CpuUsageAvg
					CpuUsagePeak = [double]$CpuUsagePeak
					MemUsageAvg = [double]$MemUsageAvg
					MemUsagePeak = [double]$MemUsagePeak
					DiskLatencyAvg = [double]$DiskLatency.Average 
					DiskLatencyPeak = [double]$DiskLatency.Maximum
					# These are Converted from KB/s to B/s (For SquaredUp)
					DiskUsageAvg = [double]$DiskUsage.Average * 1000 
					DiskUsagePeak = [double]$DiskUsage.Maximum * 1000
					NetUsageAvg = [double]$NetUsage.Average * 1000
					NetUsagePeak = [double]$NetUsage.Maximum * 1000
                }
				# Return it
				$hostObject
			}
		} Catch {
			$message = "Error Getting Host Health." + "`r`n vCenter Name : $vCenterName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
			$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		}
		Finally {
			# Disconnect from Virtual Center
			Disconnect-VIServer -Server $vc -Confirm:$false
		}
    }