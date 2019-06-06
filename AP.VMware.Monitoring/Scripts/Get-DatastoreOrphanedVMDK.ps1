#==================================================================================
# Script: 	Get-DatastoreOrphanedVMDK.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets Orphaned Virtual Disks from Datastore return all as Property Bags
#==================================================================================

# Get the named parameters
Param(
    [string]$vCenterName, 
    [string]$UserName, 
    [string]$Password, 
    [string]$Debug,
	[string]$FolderFilter,
	[string]$FileFilter
)

# Get Start Time For Script
$StartTime = (GET-DATE)

#Constants used for event logging
$SCRIPT_NAME			= 'Get-DatastoreOrphanedVMDK.ps1'
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
$GetOrphanedVMDKs = {
    Param(
        [string]$vCenterName, 
        [string]$UserName, 
        [string]$Password, 
        [string]$Debug,
		[string]$FolderFilter,
		[string]$FileFilter
    )   

    #Constants used for event logging
    $SCRIPT_NAME			= 'Get-DatastoreOrphanedVMDK.ps1'
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
		    # Get List of VMs (Layout Only)
		    $VmList = Get-View -Server $vc -ViewType VirtualMachine -Property Name,Layout

			# Get List of Used Disks From the VMs
			$UsedDiskList = $VmList | % {$_.Layout} | % {$_.Disk} | % {$_.DiskFile}

		    # Get Datastore Views
		    $DatastoreViews = Get-View -Server $vc -ViewType Datastore | Sort-Object -property Name


			# Site Recovery Manager creates -000000.vmdk and -000000-delta.vmdk files. This excludes these patterns from being displayed.
			#$FileFilter = "-ctk.vmdk|-flat.vmdk|-[0-9][0-9][0-9][0-9][0-9][0-9]\.vmdk|-[0-9][0-9][0-9][0-9][0-9][0-9]-delta\.vmdk|-xd-delta.vmdk|-xd-delta-delta.vmdk|_temporarystorage.vmdk|_identitydisk.vmdk"
			#$FolderFilter = "-basedisk-datastore-"
			
			# Loop through Datastore Views
			Foreach ($DatastoreView in $DatastoreViews) {
				Try {
					# Don't Scan non shared Datastores that have no VMs
					if ($DatastoreView.Vm.Count -eq 0 -and $DatastoreView.Summary.MultipleHostAccess -eq $false) { continue }

					# Get Datastore browser
					$DatastoreBrowser = Get-View -Server $vc $DatastoreView.browser

					# Create File Query Flags Object
					$fileQueryFlags = New-Object VMware.Vim.FileQueryFlags
					$fileQueryFlags.FileSize = $true

					# Create Search Spec
					$searchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
					$searchSpec.details = $fileQueryFlags
					$searchSpec.matchPattern = "*.vmdk"
					$searchSpec.sortFoldersFirst = $true

					# Get Results
					$rootPath = "[" + $DatastoreView.Name + "]"
					$searchResults = $DatastoreBrowser.SearchDatastoreSubFolders($rootPath, $searchSpec)
					# Set Initial Vars
					$OrphanedFileNames = "None"

					# Loop Through each Folder in Results
					Foreach ($folder in $searchResults) {
						Foreach ($file in $folder.File) {
							If ($file.Path) {
								# Convert Path to String
								$pathAsString = out-string -InputObject $file.Path

								# If this File Isn't in the list of Used VM Disks then Investigate
								If (-not ($UsedDiskList -contains ($folder.FolderPath + $file.Path))) {

									If ($FolderFilter -ne ""){
										If ($folder.FolderPath.toLower() -notmatch $FolderFilter) {
											If ($FileFilter -ne "") {
												If ($pathAsString.toLower() -notmatch $FileFilter) {
													$OrphanedFileNames += "$($folder.FolderPath)$($file.Path)" + ";"
												}																		
											} Else {
												$OrphanedFileNames += "$($folder.FolderPath)$($file.Path)" + ";"											
											}
										}							
									} else {
										If ($FileFilter -ne "") {
											If ($pathAsString.toLower() -notmatch $FileFilter) {
												$OrphanedFileNames += "$($folder.FolderPath)$($file.Path)" + ";"
											}																		
										} Else {
											$OrphanedFileNames += "$($folder.FolderPath)$($file.Path)" + ";"											
										}
									}

								}
							}
						}
					}
					$OrphanedFileNames = $OrphanedFileNames.TrimEnd('; ')

					# Report Progress.
					if ($Debug -eq $true) { 
    					[string] $message = "`r`nChecking Datastore " + $DatastoreView.Name + " for Orphaned Virtual Disks.`r`nFound : " + $OrphanedFileNames
						$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_PROPERTYBAG_CREATED,$EVENT_LEVEL_INFO, $message) 
					} 

					# Create Datastore Object
					$dsObject = [PSCustomObject]@{
						DatastoreKey = [string]$DatastoreView.MoRef.ToString()
						DatastoreName = [string]$DatastoreView.Name
						OrphanedFileNames = [string]$OrphanedFileNames
					}
					# Return it
					$dsObject			


				}Catch {
					$message = "Error Getting Info from Datastore." + "`r`n vCenter Name : $vCenterName" + "`r`nDatastore Name : " + $Datastore.Name + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
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
    $message = "Script Started for, " + $vCenterName + "`r`nFolder Filter : " + $FolderFilter + "`r`nFile Filter : " + $FileFilter
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 
} 

Try {
	# Set JobName
	$JobName = "GetOrphanedVMDK-" + $vCenterName

	# Start The Job
	Start-Job -Name $JobName -ScriptBlock $GetOrphanedVMDKs -ArgumentList $vCenterName, $UserName, $Password, $Debug, $FolderFilter, $FileFilter | Out-Null

	# Wait For Job
	Wait-Job -Name $JobName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $JobName

	# Remove Job
	Remove-Job -Name $JobName

	# Loop Through Results
	Foreach ($result in $Results) {

		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.name -match "DatastoreKey")) {
			$bag = $api.CreatePropertyBag()
			$bag.AddValue("DatastoreKey", $result.DatastoreKey)
			$bag.AddValue("DatastoreName", $result.DatastoreName)
			$bag.AddValue("OrphanedFileNames", $result.OrphanedFileNames)
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
