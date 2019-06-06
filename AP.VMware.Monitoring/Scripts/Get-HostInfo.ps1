#==================================================================================
# Script: 	Get-HostInfo.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets Info from Hosts, returns all as Property Bags
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
$SCRIPT_NAME			= 'Get-HostInfo.ps1'
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
$GetHostHealth = {
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
					$CpuUsageMax = [Math]::Round([double]($CpuUsage.Maximum /100), 2)		
					# Get Memory Usage Average/Maximum
					$MemUsage = ($Stats.Value | where {$_.Id.CounterId -eq $pcTable["mem.usage.average"]}).Value | Measure-Object -Average -Maximum
					$MemUsageAvg = [Math]::Round([double]($MemUsage.Average /100), 2)
					$MemUsageMax = [Math]::Round([double]($MemUsage.Maximum /100), 2)

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
					HostSwapUsage = [int]$HostSwapUsage
					HostBallooning = [int]$HostBallooning
					CpuReady = [double]$CpuReady
					CpuUsageAvg = [double]$CpuUsageAvg
					CpuUsageMax = [double]$CpuUsageMax
					MemUsageAvg = [double]$MemUsageAvg
					MemUsageMax = [double]$MemUsageMax
					DiskUsageAvg = [int]$DiskUsage.Average 
					DiskUsageMax = [int]$DiskUsage.Maximum
					DiskLatencyAvg = [int]$DiskLatency.Average 
					DiskLatencyMax = [int]$DiskLatency.Maximum
					NetUsageAvg = [int]$NetUsage.Average 
					NetUsageMax = [int]$NetUsage.Maximum 
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
} ### End of Script Block

#Start by setting up API object.
$api = New-Object -comObject 'MOM.ScriptAPI'

# Log Startup Message
if ($Debug -eq $true) { 
    $message = "Script Started for, " + $vCenterName
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 
} 

Try {

	$JobName = 'hostInfo' + $vCenterName

	# Start The Job
	Start-Job -Name $JobName -ScriptBlock $GetHostHealth -ArgumentList $vCenterName, $UserName, $Password, $Debug | Out-Null

	# Wait For Job
	Wait-Job -Name $JobName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $JobName

	# Remove Job
	Remove-Job -Name $JobName

	# Loop Through Results
	Foreach ($result in $Results) {

		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.name -match "HostKey")) {
			$bag = $api.CreatePropertyBag()
			$bag.AddValue("HostKey", $result.HostKey)
			$bag.AddValue("HostInMaintenance", $result.HostInMaintenance)
			$bag.AddValue("HostTotalCpuPercent", $result.HostTotalCpuPercent)
			$bag.AddValue("HostNumPhysicalCores", $result.HostNumPhysicalCores)
			$bag.AddValue("HostNumPhysicalThreads", $result.HostNumPhysicalThreads)
			$bag.AddValue("HostTotalVirtualCPU", $result.HostTotalVirtualCPU)
			$bag.AddValue("HostvCpuPhysicalCpuRatio", $result.HostvCpuPhysicalCpuRatio)
			$bag.AddValue("HostTotalRamPercent", $result.HostTotalRamPercent)
			$bag.AddValue("HostSwapUsage", $result.HostSwapUsage)
			$bag.AddValue("HostBallooning", $result.HostBallooning)
			$bag.AddValue("CpuReady", $result.CpuReady)
			$bag.AddValue("CpuUsageAvg", $result.CpuUsageAvg)
			$bag.AddValue("CpuUsageMax", $result.CpuUsageMax)
			$bag.AddValue("MemUsageAvg", $result.MemUsageAvg)
			$bag.AddValue("MemUsageMax", $result.MemUsageMax)
			$bag.AddValue("DiskUsageAvg", $result.DiskUsageAvg)
			$bag.AddValue("DiskUsageMax", $result.DiskUsageMax)
			$bag.AddValue("NetUsageAvg", $result.NetUsageAvg)
			$bag.AddValue("NetUsageMax", $result.NetUsageMax)
			$bag.AddValue("DiskLatencyAvg", $result.DiskLatencyAvg)
			$bag.AddValue("DiskLatencyMax", $result.DiskLatencyMax)
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
