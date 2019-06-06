#==================================================================================
# Script: 	Discover-Datastores.ps1
# Date:		21/01/19
# Author: 	Andi Patrick
# Purpose:	Discover Datastores from a given virtual Center
#			Also discocers relationships to Hosts and Clusters
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
$SCRIPT_NAME			= 'Discover-Datastores.ps1'
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
$DiscoverDatastoresBlock = {
# Get the named parameters
	Param(
		[string]$vCenterFullName, 
		[string]$UserName, 
		[string]$Password, 
		[string]$Debug 
	)

	#Constants used for event logging
	$SCRIPT_NAME			= 'Discover-Datastores.ps1'
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
			
			# Get Cluster Views (Datastores Only)
			$clusterViews = Get-View -Server $vc -ViewType ClusterComputeResource -Property Name, Datastore

			# Get Host Views (Datastores Only)
			$hostViews = Get-View -Server $vc -ViewType HostSystem -Property Name, Datastore

			# Get DatstoreViews
			$datastoreViews = Get-View -Server $vc -ViewType Datastore -Property Name, Summary

		
			# Loop Through Datastores 
			Foreach ($datastoreView in $datastoreViews) {

				# Get Containment References
			
				# Store Clusters References
				[System.Collections.ArrayList]$ClusterMoRefList = @()
				Foreach ($clusterView in $clusterViews) {
					Foreach ($datastoreRef in $clusterView.Datastore) {
						If ($datastoreRef -eq $datastoreView.MoRef.ToString()) {						
							[void]$ClusterMoRefList.Add($clusterView.MoRef.ToString())
							Break
						}
					}
				}

				# Store Host Refereneces
				[System.Collections.ArrayList]$HostMoRefList = @()
				Foreach ($hostView in $hostViews){
					Foreach ($datastoreRef in $hostView.Datastore){
						If ($datastoreRef -eq $datastoreView.MoRef.ToString()){
							[void]$HostMoRefList.Add($hostView.MoRef.ToString())
							Break
						}
					}
				}

				#$datastoreView.Summary
				# Create Datastore Object
				$datastoreObject = [PSCustomObject]@{
					vCenterFullName = $vCenterFullName.ToString()
					Name = $datastoreView.Name.ToString()
					MoRef = $datastoreView.MoRef.ToString()
					ObjectType = $datastoreView.MoRef.Type.ToString()
					Capacity = [Math]::Round([Double]$datastoreView.Summary.Capacity / 1024 / 1024 /1024, 2)
					MultipleHostAccess = $datastoreView.Summary.MultipleHostAccess
					Type = $datastoreView.Summary.Type
					HostMoRefList = $HostMoRefList
					ClusterMoRefList = $ClusterMoRefList
				}

				# return Object
				$datastoreObject
			}
		} Catch {
			$message = "Error Getting Datastore Info from Virtual Center." + "`r`n vCenter Name : $vCenterFullName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
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
	$JobName = "DiscoverDatastores-" + $vCenterFullName
	Start-Job -Name $JobName -ScriptBlock $DiscoverDatastoresBlock -ArgumentList $vCenterFullName, $UserName, $Password, $Debug | Out-Null

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
			# Create a Datastore Instance
			$datastoreInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.Datastore']$")
			# Add Virtual Center Reference
			$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
			# Add Parent Group Reference
			$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.DatastoresGroup']/Name$", "Datastores")
			# Add Display Name Property from System.Entity
			$datastoreInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $result.Name)
			# Add Properties
			$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.Datastore']/Name$", $result.Name)
			$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.Datastore']/MoRef$", $result.MoRef)
			$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.Datastore']/ObjectType$", $result.ObjectType)
			$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.Datastore']/Capacity$", $result.Capacity)
			$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.Datastore']/Type$", $result.Type)
			$datastoreInstance.AddProperty("$MPElement[Name='AP.VMware.Datastore']/MultipleHostAccess$", $result.MultipleHostAccess)

			# Add Datastore Instance to Discovery Data
			$DiscoveryData.AddInstance($datastoreInstance)

			# Cluster Containment relationships
			Foreach ($clusterMoRefListItem in $result.ClusterMoRefList) {
				Try {
					# First Let's make sure it exist in SCOM before adding a Relationship
					$clusterClassInstance = Get-SCOMClassInstance -Class (Get-SCOMClass -Name AP.VMware.Cluster) | ?{($_."[AP.VMware.Cluster].MoRef").Value -eq  $clusterMoRefListItem}
					If ($clusterClassInstance -ne $null) {
						# Create Cluster Object for Relationship
						$ClusterInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.Cluster']$")
						# Add Virtual Center Reference
						$ClusterInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
						# Add Parent Group Reference
						$ClusterInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.ClustersGroup']/Name$", "Clusters")
						# Add MoRef (KEY)
						$ClusterInstance.AddProperty("$MPElement[Name='AP.VMware.Cluster']/MoRef$", $clusterMoRefListItem)

						# Create Cluster Relationship if Needed
						$clusterRelInstance = $DiscoveryData.CreateRelationshipInstance("$MPElement[Name='AP.VMware.ClusterContainsDatastores']$")
						$clusterRelInstance.Source = $ClusterInstance
						$clusterRelInstance.Target = $datastoreInstance
						$DiscoveryData.AddInstance($clusterRelInstance)								
					}
					
				} Catch {
					Continue
				}
			}

			# Host Containment relationships
			Foreach ($hostMoRefListItem in $result.HostMoRefList) {
				Try {
					# First Let's make sure it exist in SCOM before adding a Relationship
					$hostClassInstance = Get-SCOMClassInstance -Class (Get-SCOMClass -Name AP.VMware.Host) | ?{($_."[AP.VMware.Host].MoRef").Value -eq  $hostMoRefListItem}
					If ($hostClassInstance -ne $null) {
						# Create Host Object for Relationship
						$HostInstance = $DiscoveryData.CreateClassInstance("$MPElement[Name='AP.VMware.Host']$")
						# Add Virtual Center Reference
						$HostInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter']/FullName$", $vCenterFullName)
						# Add Parent Group Reference
						$HostInstance.AddProperty("$MPElement[Name='AP.VMware.VirtualCenter.HostsGroup']/Name$", "Hosts")
						# Add MoRef (KEY)
						$HostInstance.AddProperty("$MPElement[Name='AP.VMware.Host']/MoRef$", $hostMoRefListItem)

						# Create Host Relationship if Needed
						$hostRelInstance = $DiscoveryData.CreateRelationshipInstance("$MPElement[Name='AP.VMware.HostContainsDatastores']$")
						$hostRelInstance.Source = $HostInstance
						$hostRelInstance.Target = $datastoreInstance
						$DiscoveryData.AddInstance($hostRelInstance)								
					}
					
				} Catch {
					Continue
				}
			}

		}	
	}

	# Log Discovery Data if Debug Enabled
	if ($Debug -eq $true) { 
		$message = "Datastores Discovered on $vCenterFullName : `r`n" + $instanceList
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
