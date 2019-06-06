#==================================================================================
# Script: 	Discover-Hosts.ps1
# Date:		21/01/19
# Author: 	Andi Patrick
# Purpose:	Discovers Hosts on a given Virtual Center
#			also discovers Cluster Containment Relationships
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
$SCRIPT_NAME			= 'Discover-Hosts.ps1'
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
$DiscoverHosts = {
# Get the named parameters
	Param(
		[string]$vCenterFullName, 
		[string]$UserName, 
		[string]$Password, 
		[string]$Debug 
	)

	#Constants used for event logging
	$SCRIPT_NAME			= 'Discover-Hosts.ps1'
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
			# Get Host Views
			$hostViews = Get-View -Server $vc -ViewType HostSystem -Property Name, Summary.Hardware, Hardware

			# Get Cluster Views
			$clusterViews = Get-View -Server $vc -ViewType ClusterComputeResource -Property Name, Host
			
			# Loop Through Each Cluster
			Foreach ($hostView in $hostViews){

				# Get Serial Number
				$SerialNumber  = ($hostView.Hardware.SystemInfo.OtherIdentifyingInfo | where {$_.IdentifierType.Key -eq "ServiceTag"}).IdentifierValue

				$IsClustered = $false
				$ClusterRef = ""
				# Loop Through Each Cluster
				Foreach ($clusterView in $clusterViews){
					Foreach ($hostRef in $clusterView.Host) {
						if ($hostRef -eq $vmHostView.MoRef) {
							$IsClustered = $true
							$ClusterRef = $clusterView.MoRef.ToString()
						}
					}
				}

				# Create Host Object
				$hostObject = [PSCustomObject]@{
					vCenterFullName = [string]$vCenterFullName.ToString()
					Name = [string]$hostView.Name.ToString()
					MoRef = [string]$hostView.MoRef.ToString()
					ObjectType = [string]$hostView.MoRef.Type.ToString()
					Vendor = [string]$hostView.Summary.Hardware.Vendor.ToString()
					Model = [string]$hostView.Summary.Hardware.Model.ToString()
					SerialNumber = [string]$SerialNumber
					CpuModel = [string]$hostView.Summary.Hardware.CpuModel.ToString()
					CpuMhz = [int]$hostView.Summary.Hardware.CpuMhz
					NumCpu = [int]$hostView.Summary.Hardware.NumCpuPkgs
					NumCpuCores = [int]$hostView.Summary.Hardware.NumCpuCores
					NumCpuThreads = [int]$hostView.Summary.Hardware.NumCpuThreads
					Memory = [Math]::Round($hostView.Summary.Hardware.MemorySize / 1024 / 1024 / 1024, 0)
					IsClustered = $IsClustered
					ClusterRef = $ClusterRef

				}
				# Return it
				$hostObject
			}
		} Catch {
			$message = "Error Getting Host Info from Virtual Center." + "`r`n vCenter Name : $vCenterFullName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
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
	$JobName = "DiscoverHosts-" + $vCenterFullName
	Start-Job -Name $JobName -ScriptBlock $DiscoverHosts -ArgumentList $vCenterFullName, $UserName, $Password, $Debug | Out-Null

	# Wait For Job
	Wait-Job -Name $JobName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $JobName

	# Remove Job
	Remove-Job -Name $JobName

	# Create Discovery Data Object
	$DiscoveryData = $api.CreateDiscoveryData(0, $sourceId,  $managedEntityId)

	# Loop Through Results
	Foreach ($result in $Results) {
		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.name -match "vCenterFullName")) {		
			$instanceList += "`r`n" + $result.Name
			# Create a Host Instance
			$hostInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.Host']$")
			# Add Virtual Center Reference
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
			# Add Parent Group Reference
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.HostsGroup']/Name$", "Hosts")
			# Add Display Name Property from System.Entity
			$hostInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $result.Name)
			# Add Properties
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/Name$", $result.Name)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/MoRef$", $result.MoRef)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/ObjectType$", $result.ObjectType)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/IsClustered$", $result.IsClustered)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/Vendor$", $result.Vendor)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/Model$", $result.Model)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/SerialNumber$", $result.SerialNumber)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/CpuModel$", $result.CpuModel)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/CpuMhz$", $result.CpuMhz)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/NumCpu$", $result.NumCpu)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/NumCpuCores$", $result.NumCpuCores)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/NumCpuThreads$", $result.NumCpuThreads)
			$hostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/Memory$", $result.Memory)

			$DiscoveryData.AddInstance($hostInstance)

			If ($result.IsClustered -eq $true) {
				Try {
					# First Let's make sure it exist in SCOM before adding a Relationship
					$ClusterClassInstance = Get-SCOMClassInstance -Class (Get-SCOMClass -Name AP.VMware.Cluster) | ?{($_."[AP.VMware.Cluster].MoRef").Value -eq  $result.ClusterRef}
					If ($ClusterClassInstance -ne $null) {
						#$ClusterInstance = Get-SCOMClassInstance -Class (Get-SCOMClass -Name AP.VMware.Cluster) | ?{$_.DisplayName -eq $ClusterName}
						# Create Cluster Object for Relationship
						$ClusterInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.Cluster']$")
						# Add Virtual Center Reference
						$ClusterInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
						# Add Parent Group Reference
						$ClusterInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.ClustersGroup']/Name$", "Clusters")
						# Add MoRef (KEY)
						$ClusterInstance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/MoRef$", $result.ClusterRef)

						# Create Cluster Relationship if Needed
						$relationshipInstance = $DiscoveryData.CreateRelationshipInstance("$MPElement[Name='AP.VMware.ClusterContainsHosts']$")
						$relationshipInstance.Source = $ClusterInstance
						$relationshipInstance.Target = $hostInstance
						$DiscoveryData.AddInstance($relationshipInstance)								
					}
			
				} Catch {}
			}


		}	
	}


	# Log Discovery Data if Debug Enabled
	if ($Debug -eq $true) { 
		$message = "Hosts Discovered on $vCenterFullName : `r`n" + $instanceList
		$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_DISCOVERY_CREATED,$EVENT_LEVEL_INFO, $message) 
	} 

	$DiscoveryData

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
