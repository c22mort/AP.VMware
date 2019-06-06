#==================================================================================
# Script: 	Get-DatastoreOrphanedVM.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets Orphaned Virtual Machines from Datastore return all as Property Bags
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
$SCRIPT_NAME			= 'Get-DatastoreOrphanedVM.ps1'
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
$Check_ForOrphanedVMs = {
    Param(
        [string]$vCenterName, 
        [string]$UserName, 
        [string]$Password, 
        [string]$Debug
    )   

    #Constants used for event logging
    $SCRIPT_NAME			= 'Get-DatastoreOrphanedVM.ps1'
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
	    Start-Sleep -Seconds 5
	    Try {
	        $vc = Connect-VIServer $vCenterName -User $UserName -Password $Password -Force:$true -NotDefault	
	    } Catch {
		    $message = "Error Connecting to Virtual Center" + "`r`n" + $_
		    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		    Exit		
	    }
    }

    If ($vc) {
       	# At this point Modules Should be loaded and vCenter Connected
    	Try {
		    # Get List of VMs (Layout Only)
		    $VmList = Get-View -Server $vc -ViewType VirtualMachine -Property Config.Files.VmPathName | Where {-not $_.Config.Template} 
		    # Get List of Vmx Files From the VMs
		    $VmConfigFileList = $VmList | % {$_.Config.Files.VmPathName} 

		    # Get Datastore Views
		    $DatastoreViews = Get-View -Server $vc -ViewType Datastore | Sort-Object -property Name

    		# Loop Through Datastores
	    	Foreach ($DatastoreView in $DatastoreViews) {
                Try {

				    # Don't Scan non shared Datastores that have no VMs
				    if (-not ($DatastoreView.Vm.Count -eq 0 -and $DatastoreView.Summary.MultipleHostAccess -eq $false)) {

					    # Get Datastore browser
					    $DatastoreBrowser = Get-View -Server $vc $DatastoreView.browser

					    # Create File Query Flags Object
					    $fileQueryFlags = New-Object VMware.Vim.FileQueryFlags
					    #$fileQueryFlags.FileSize = $true

					    # Create Search Spec
					    $searchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
					    $searchSpec.details = $fileQueryFlags
					    $searchSpec.matchPattern = "*.vmx"
					    $searchSpec.sortFoldersFirst = $true

					    # Get Results
					    $rootPath = "[" + $DatastoreView.Name + "]"
					    $searchResults = $DatastoreBrowser.SearchDatastoreSubFolders($rootPath, $searchSpec)	

					    # Set Initial Vars
					    $OrphanedFileNames = ""

					    # Loop Through each Folder in Results
					    foreach ($folder in $searchResults) {
						    foreach ($file in $folder.File) {
							    if ($file.Path) {
								    $FullPath = $folder.FolderPath + $file.Path
								    if (-not $VmConfigFileList.Contains($FullPath)) {
									    # Orphaned Vm
									    $OrphanedFileNames += $FullPath + "; "
								    }
							    }
						    }
					    }
					    $OrphanedFileNames = $OrphanedFileNames.TrimEnd('; ')

					    # Report Progress.
                        if ($Debug -eq $true) { 
    					    [string] $message = "`r`nChecking Datastore " + $DatastoreView.Name + " for Orphaned VirtualMachines : " + $OrphanedFileNames
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
				    }


                } Catch {
				    $message = "Error Getting Info from Datastore." + "`r`n vCenter Name : $vCenterName" + "`r`nDatastore Name : " + $DatastoreView.Name + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
				    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
				    Continue
                }
            } # End of Datastore For Each

        } Catch {
		    $message = "Error Getting VMs and Datastores from Virtual Center." + "`r`n vCenter Name : $vCenterName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
		    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
        } Finally {
		    # Disconnect from Virtual Center
		    Disconnect-VIServer -Server $vc -Confirm:$false
        }

    }
}

#Start by setting up API object.
$api = New-Object -comObject 'MOM.ScriptAPI'

# Log Startup Message
if ($Debug -eq $true) { 
    $message = "Script Started for, " + $vCenterName
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 
} 

Try {
	# Start The Job
	Start-Job -Name "GetDatastoreOrphanedVM" -ScriptBlock $Check_ForOrphanedVMs -ArgumentList $vCenterName, $UserName, $Password, $Debug | Out-Null

	# Wait For Job
	Wait-Job -Name "GetDatastoreOrphanedVM" | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name "GetDatastoreOrphanedVM"

	# Remove Job
	Remove-Job -Name "GetDatastoreOrphanedVM"

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
