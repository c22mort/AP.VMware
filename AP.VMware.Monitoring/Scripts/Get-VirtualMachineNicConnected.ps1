#==================================================================================
# Script: 	Get-VirtualMachineNicConnected.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets Virtual Machines Nic Connected State from return all as Property Bags
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
$SCRIPT_NAME			= 'Get-VirtualMachineNicConnected.ps1'
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
$Check_vmNicConnected = {
    Param(
        [string]$vCenterName, 
        [string]$UserName, 
        [string]$Password, 
        [string]$Debug
    )   

	    #Constants used for event logging
    $SCRIPT_NAME			= 'Get-VirtualMachineNicConnected.ps1'
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
		Try {
			# Get Network Adapters From All VirtualMachines
			$niclist = Get-VM -Server $vc | Get-NetworkAdapter 
			Foreach ($nic in $niclist) {
			    # Report Progress.
                if ($Debug -eq $true) { 
    				[string] $message = "`r`nChecking Nic Connected state for :  " + $nic.Parent
                    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_PROPERTYBAG_CREATED,$EVENT_LEVEL_INFO, $message) 
                } 

				Try {
					# Create Nic Object
					$nicObject = [PSCustomObject]@{
						VirtualMachineName = [string]$nic.Parent
						MacAddress = [string]$nic.MacAddress
						Connected = [string]$nic.ConnectionState.Connected
						StartConnected = [string]$nic.ConnectionState.StartConnected
					}
					# Return it
					$nicObject
				
				} Catch {
					Continue				
				}
			}

		} Catch {
		    $message = "Error Getting Nic Info." + "`r`n vCenter Name : $vCenterName" + "`r`nError : " + $_ + "`r`n" + $_.InvocationInfo.PositionMessage 
		    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
		} Finally {
		    # Disconnect from Virtual Center
		    Disconnect-VIServer -Server $vc -Confirm:$false
		}

	}
} ### END OF SCRIPT Block

#Start by setting up API object.
$api = New-Object -comObject 'MOM.ScriptAPI'

# Log Startup Message
if ($Debug -eq $true) { 
    $message = "Script Started for, " + $vCenterName
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 
} 

Try {
	# Start The Job
	$ScriptName = "vmNicConnected" + $vCenterName
	Start-Job -Name $ScriptName -ScriptBlock $Check_vmNicConnected -ArgumentList $vCenterName, $UserName, $Password, $Debug | Out-Null

	# Wait For Job
	Wait-Job -Name $ScriptName | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name $ScriptName

	# Loop Through Results
	Foreach ($result in $Results) {

		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.name -match "MacAddress")) {
			$bag = $api.CreatePropertyBag()
			$bag.AddValue("VirtualMachineName", $result.VirtualMachineName)
			$bag.AddValue("MacAddress", $result.MacAddress)
			$bag.AddValue("Connected", $result.Connected)
			$bag.AddValue("StartConnected", $result.StartConnected)
			#$api.Return($bag)
			$bag	
		}	
	}

	# Remove Job
	Remove-Job -Name $ScriptName

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