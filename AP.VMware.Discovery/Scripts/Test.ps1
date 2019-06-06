	# Get the named parameters
	Param(
		[string]$vCenterFullName, 
		[string]$UserName, 
		[string]$Password, 
		[string]$Debug 
	)

	#Constants used for event logging
	$SCRIPT_NAME			= 'Discover-VirtualMachines.ps1'
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
			$clusterViews = Get-View -Server $vc -ViewType ClusterComputeResource -Property Name, Host

			# Get Host Views (Datastores Only)
			$hostViews = Get-View -Server $vc -ViewType HostSystem -Property Name, Vm

			# Get DatstoreViews
			$datastoreViews = Get-View -Server $vc -ViewType Datastore -Property Name, Vm

			# Get VM Views
			$vmViews = Get-View -Server $vc -ViewType VirtualMachine -Property Name, Config.Version, Guest, Summary.Config.VmPathName, Config.Hardware.Device

			# Get ALL Windows Computers from SCOM
			$computerClassInstances = Get-SCOMClassInstance -Class (Get-SCOMClass -Name Microsoft.Windows.Computer) 

			Foreach ($vmView in $vmViews) {
				$WindowsComputerRef= ""

				# Get Windows Computer Reference
				Foreach ($computerClass in $computerClassInstances) {
					If ($vmView.Guest.HostName -eq $computerClass.("[Microsoft.Windows.Computer].PrincipalName").Value) {
						$WindowsComputerRef = $computerClass.("[Microsoft.Windows.Computer].PrincipalName").Value					
					}
				}

				# Create Host Reference
				$HostMoRef = ""
				$ClusterMoRef = ""
				Foreach ($hostView in $hostViews) {
					Foreach ($vmRef in $hostView.Vm) {
						If ($vmRef.ToString() -eq $vmView.MoRef.ToString()) {
							$HostMoRef = $hostView.MoRef.ToString()
							# Figure out which Cluster this Host s in
							Foreach ($clusterView in $clusterViews) {
								Foreach ($hostRef in $clusterView.Host) {
									If ($hostRef -eq $HostMoRef) {
										$ClusterMoRef = $clusterView.MoRef.ToString()
										Break
									}
								}
							}
							Break
						}
					}
				}

				# Create Datastore Reference
				$DatastoreMoRef = ""
				Foreach ($datastoreView in $datastoreViews) {
					Foreach ($vmRef in $datastoreView.Vm) {
						If ($vmRef.ToString() -eq $vmView.MoRef.ToString()) {
							$DatastoreMoRef = $datastoreView.MoRef.ToString()
							Break
						}
					}
				}	
			
				# Get Basic Disk Info
				[Double]$diskCapacity = 0
				[int]$diskCount = 0
				Foreach ($virtualDevice in $vmView.Config.Hardware.Device) {
					If ($virtualDevice.GetType() -eq [VMware.Vim.VirtualDisk]) {
						$diskCount += 1
						$diskCapacity += [Double]$virtualDevice.CapacityInKB / 1024 / 1024
					}
				}

				# Get Disk Info From Guest (VM Tools Neeeded)
				[System.Collections.ArrayList]$vmDiskList = @()
				Foreach ($disk in $vmView.Guest.Disk) {
					$diskObject = [PSCustomObject]@{
						Name = $disk.DiskPath		
						Capacity = [Math]::Round($disk.Capacity / 1024 / 1024 / 1024, 2)
						#FreeSpace = [Math]::Round($disk.FreeSpace / 1024 / 1024 / 1024, 2)
						#UsedSpace = [Math]::Round(($disk.Capacity - $disk.FreeSpace) / 1024 / 1024 / 1024, 2)
					}
					[void]$vmDiskList.Add($diskObject)
				}

				# Get Nic Info from Guest (VM Tools Needed)
				[System.Collections.ArrayList]$vmNicList = @()
				Foreach ($nic in $vmView.Guest.Net) {

					# Get IpAddresses
					[string]$IpAddresses = ""
					Foreach ($ip in $nic.IpAddress) {
						$IpAddresses += $ip + ";"					
					}
					$IpAddresses = $IpAddresses.TrimEnd(";")

					# Get DnsAddresses
					[string]$DnsAddresses = ""
					Foreach ($dns in $nic.DnsConfig.IpAddress) {
						$DnsAddresses += $dns + ";"					
					}
					$DnsAddresses = $DnsAddresses.TrimEnd(";")

					# Create NIC Object
					$nicObject = [PSCustomObject]@{
						MacAddress = $nic.MacAddress
						Network = $nic.Network
						IpAddress = $IpAddresses
						DnsDomain = $nic.DnsConfig.DomainName
						DnsAddress = $DnsAddresses
					}				
					# Add NicObject to List
					[void]$vmNicList.Add($nicObject)
				}

				#$vmView.Summary
				# Create Datastore Object
				$vmObject = [PSCustomObject]@{
					vCenterFullName = $vCenterFullName.ToString()
					Name = $vmView.Name.ToString()
					Version = $vmView.Config.Version.ToString()
					MoRef = $vmView.MoRef.ToString()
					ObjectType = $vmView.MoRef.Type
					HostName = $vmView.Guest.HostName
					IpAddress = $vmView.Guest.IpAddress
					StoragePath = $vmView.Summary.Config.VmPathName
					DiskCount = $diskCount
					DiskCapacity = [Math]::Round($diskCapacity, 2)
					DiskList = $vmDiskList
					NicList = $vmNicList
					HostMoRef = $HostMoRef
					DatastoreMoRef = $DatastoreMoRef
					ClusterMoRef = $ClusterMoRef
					WindowsComputerRef = $WindowsComputerRef
				}

				# return Object
				$vmObject
			}

		} Catch {
			$message = "Error Getting Virtual Machine Info from Virtual Center." + "`r`n vCenter Name : $vCenterFullName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
			$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		}
		Finally {
			# Disconnect from Virtual Center
			Disconnect-VIServer -Server $vc -Confirm:$false
		}
	}