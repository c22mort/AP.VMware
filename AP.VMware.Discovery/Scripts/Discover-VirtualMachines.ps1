#==================================================================================
# Script: 	Discover-VirtualMachines.ps1
# Date:		21/01/19
# Author: 	Andi Patrick
# Purpose:	Discover Virtual Machines from Virtual Center
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
$SCRIPT_NAME			= 'Discover-VirtualMachines.ps1'
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
$DiscoverVirtualMachinesBlock = {
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
	# Start The Job
	$JobName = "DiscoverVirtualMachines-" + $vCenterFullName
	Start-Job -Name $JobName -ScriptBlock $DiscoverVirtualMachinesBlock -ArgumentList $vCenterFullName, $UserName, $Password, $Debug | Out-Null

	# Wait For Job
	Wait-Job -Name $JobName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $JobName

	# Remove Job
	Remove-Job -Name $JobName

	# Create Discovery Data Object
	$DiscoveryData = $api.CreateDiscoveryData(0, $sourceId,  $managedEntityId)

	# Only Create Discovery Data if There are Results
	If ($Results.Length -ne 0) {
		# Loop Through Results
		Foreach ($result in $Results) {
			# If Result Contains a Property called vCenterFullName
			If ([bool]($result.PSobject.Properties.name -match "vCenterFullName")) {		
			
				# Create a VirtualMachine Instance
				$vmInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.VirtualMachine']$")
				# Add Virtual Center Reference
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
				# Add Parent Group Reference
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.VirtualMachinesGroup']/Name$", "Virtual Machines")
				# Add Display Name Property from System.Entity
				$vmInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $result.Name)
				# Add Properties
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/Name$", $result.Name)
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/HardwareVersion$", $result.Version)
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/MoRef$", $result.MoRef)
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/ObjectType$", $result.ObjectType)
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/StoragePath$", $result.StoragePath)
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/HostName$", $result.HostName)
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/IpAddress$", $result.IpAddress)
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/NumOfDisks$", $result.DiskCount)
				$vmInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/TotalDiskCapacity$", $result.DiskCapacity)

				$DiscoveryData.AddInstance($vmInstance)

				# Add Disks
				Foreach ($disk in $result.DiskList) {
					# Create a Disk Instance
					$diskInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.VirtualMachine.Disk']$")
					# Add Virtual Center Reference
					$diskInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
					# Add Parent Group Reference
					$diskInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.VirtualMachinesGroup']/Name$", "Virtual Machines")
					# Add parent VM Key
					$diskInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/MoRef$", $result.MoRef)
					# Add Display Name Property from System.Entity
					$diskInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $disk.Name)
					# Add Properties
					$diskInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine.Disk']/DiskPath$", $disk.Name)
					$diskInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine.Disk']/Capacity$", $disk.Capacity)
					$DiscoveryData.AddInstance($diskInstance)
				}

				# Add Nics
				Foreach ($nic in $result.NicList) {
					# Create a Nic Instance
					$nicInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.VirtualMachine.Nic']$")
					# Add Virtual Center Reference
					$nicInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
					# Add Parent Group Reference
					$nicInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.VirtualMachinesGroup']/Name$", "Virtual Machines")
					# Add parent VM Key
					$nicInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine']/MoRef$", $result.MoRef)
					# Add Display Name Property from System.Entity
					$nicInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $nic.MacAddress)
					# Add Properties
					$nicInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine.Nic']/MacAddress$", $nic.MacAddress)
					$nicInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine.Nic']/Network$", $nic.Network)
					$nicInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine.Nic']/IPAddress$", $nic.IpAddress)
					$nicInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine.Nic']/DnsDomain$", $nic.DnsDomain)
					$nicInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualMachine.Nic']/DnsAddress$", $nic.DnsAddress)
					$DiscoveryData.AddInstance($nicInstance)
				}

				# Add Windows ComputerRef
				If ($result.WindowsComputerRef -ne "") {

					# Create WindowsComputerReference
					$windowsComputerClassInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='Windows!Microsoft.Windows.Computer']$")
					# Add PrincipalName (KEY)
					$windowsComputerClassInstance.AddProperty("$MPElement[Name='Windows!Microsoft.Windows.Computer']/PrincipalName$", $result.WindowsComputerRef)

					# Create Relationship
					$windowsCompueterRelInstance = $DiscoveryData.CreateRelationshipInstance("$MPElement[Name='AP.VMware.WindowsComputerContainsVirtualMachine']$")
					$windowsCompueterRelInstance.Source = $windowsComputerClassInstance
					$windowsCompueterRelInstance.Target = $vmInstance
					$DiscoveryData.AddInstance($windowsCompueterRelInstance)		

				}

				# Add Cluster Reference
				If ($result.ClusterMoRef -ne "") {
					Try {
						# First Let's make sure it exist in SCOM before adding a Relationship
						$clusterClassInstance = Get-SCOMClassInstance -Class (Get-SCOMClass -Name AP.VMware.Cluster) | ?{($_."[AP.VMware.Cluster].MoRef").Value -eq  $result.ClusterMoRef}
						If ($clusterClassInstance -ne $null) {
							# Create Cluster Object for Relationship
							$ClusterInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.Cluster']$")
							# Add Virtual Center Reference
							$ClusterInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
							# Add Parent Group Reference
							$ClusterInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.ClustersGroup']/Name$", "Clusters")
							# Add MoRef (KEY)
							$ClusterInstance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/MoRef$", $result.ClusterMoRef)

							# Create Cluster Relationship if Needed
							$clusterRelInstance = $DiscoveryData.CreateRelationshipInstance("$MPElement[Name='AP.VMware.ClusterContainsVirtualMachines']$")
							$clusterRelInstance.Source = $ClusterInstance
							$clusterRelInstance.Target = $vmInstance
							$DiscoveryData.AddInstance($clusterRelInstance)								
						}
					
					} Catch {
					}
				}

				# Add Host Reference
				If ($result.HostMoRef -ne "") {
					Try {
						# First Let's make sure it exist in SCOM before adding a Relationship
						$hostClassInstance = Get-SCOMClassInstance -Class (Get-SCOMClass -Name AP.VMware.Host) | ?{($_."[AP.VMware.Host].MoRef").Value -eq  $result.HostMoRef}
						If ($hostClassInstance -ne $null) {
							# Create Host Object for Relationship
							$HostInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.Host']$")
							# Add Virtual Center Reference
							$HostInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
							# Add Parent Group Reference
							$HostInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.HostsGroup']/Name$", "Hosts")
							# Add MoRef (KEY)
							$HostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/MoRef$", $result.HostMoRef)

							# Create Host Relationship if Needed
							$hostRelInstance = $DiscoveryData.CreateRelationshipInstance("$MPElement[Name='AP.VMware.HostContainsVirtualMachines']$")
							$hostRelInstance.Source = $HostInstance
							$hostRelInstance.Target = $vmInstance
							$DiscoveryData.AddInstance($hostRelInstance)								
						}
					
					} Catch {
					}
				}

			
				# Add Datastore Reference
				If ($result.DatastoreMoRef -ne "") {

					Try {
						# First Let's make sure it exist in SCOM before adding a Relationship
						$datastoreClassInstance = Get-SCOMClassInstance -Class (Get-SCOMClass -Name AP.VMware.Datastore) | ?{($_."[AP.VMware.Datastore].MoRef").Value -eq  $result.DatastoreMoRef}
						If ($datastoreClassInstance -ne $null) {
							# Create Host Object for Relationship
							$datastoreInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.Datastore']$")
							# Add Virtual Center Reference
							$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
							# Add Parent Group Reference
							$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.DatastoresGroup']/Name$", "Datastores")
							# Add MoRef (KEY)
							$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.Datastore']/MoRef$", $result.DatastoreMoRef)

							# Create Datastore Relationship if Needed
							$datastoreRelInstance = $DiscoveryData.CreateRelationshipInstance("$MPElement[Name='AP.VMware.DatastoreContainsVirtualMachines']$")
							$datastoreRelInstance.Source = $datastoreInstance
							$datastoreRelInstance.Target = $vmInstance
							$DiscoveryData.AddInstance($datastoreRelInstance)								
						}
					
					} Catch {
					}
				}

				$instanceList += "`r`n" + $result.Name
			}	
		}

		# Log Discovery Data if Debug Enabled
		if ($Debug -eq $true) { 
			$message = "Virtual Machines Discovered on $vCenterFullName : `r`n" + $instanceList
			$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_DISCOVERY_CREATED,$EVENT_LEVEL_INFO, $message) 
		} 
	
		# Return Discovery Data
		$DiscoveryData
	
	}


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
