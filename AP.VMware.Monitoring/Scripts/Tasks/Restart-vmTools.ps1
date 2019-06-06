#==================================================================================
# Script: 	Restart-vmTools.ps1
# Date:		21/05/19
# Author: 	Andi Patrick
# Purpose:	Restart vmTools Service on a virtual Machine
#==================================================================================

# Get the named parameters
Param(
    [string]$ServerName
)

# Get Start Time For Script
$StartTime = (GET-DATE)

#Constants used for event logging
$SCRIPT_NAME			= 'Restart-vmTools.ps1'
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

# Log Startup Message
$message = "Script Started, Restarting VMTools Service on $ServerName"
$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 

Try {

	# Get Service
	$Service = Get-WmiObject -Class win32_service -computer $ServerName -Namespace "root\cimv2" | Where {$_.Name -eq "VMTools" }

    If ($Service -ne $null) {
		Try {
            Write-Output "Stopping Service....." 
            $stopInfo = $Service.StopService()	
	        Sleep 2
        	$Service = Get-WmiObject -Class win32_service -computer $ServerName -Namespace "root\cimv2" | Where {$_.Name -eq "VMTools" }
			Write-Output $Service.State
		} Catch {
			Write-Output "Couldn't Stop VM Tools Service : $_"
		}
		Try {
            Write-Output "Starting Service....." 
	        $startInfo = $Service.StartService()	
	        Sleep 2
        	$Service = Get-WmiObject -Class win32_service -computer $ServerName -Namespace "root\cimv2" | Where {$_.Name -eq "VMTools" }
			Write-Output $Service.State
            If ($Service.State -eq "Running") {
                Write-Output "Resetting Alert"
                $alerts = Get-SCOMAlert | Where-Object {$_.Name -eq "VM Tools Alert" -And $_.ResolutionState -eq “0” -And $_.MonitoringObjectDisplayName -eq "$ServerName"}
                ForEach ($alert in $alerts) {
                    $monitor = get-ScomMonitor -Id $alert.MonitoringRuleId
                    $alertChange = Get-SCOMClassInstance -id $alert.MonitoringObjectId | foreach {$_.ResetMonitoringState($monitor)}
                }
            }
		} Catch {
			Write-Output "Couldn't Start VM Tools Service : $_"			
		}
    }
} Catch {
	$message = "Error : " + $_ 
	$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR,$message)
}

# Get End Time For Script
$EndTime = (GET-DATE)
$TimeTaken = NEW-TIMESPAN -Start $StartTime -End $EndTime
$Seconds = [math]::Round($TimeTaken.TotalSeconds, 2)
    
# Log Finished Message
$message = "Script Finished! Took $Seconds Seconds to Complete!"
$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ENDED,$EVENT_LEVEL_INFO, $message) 
