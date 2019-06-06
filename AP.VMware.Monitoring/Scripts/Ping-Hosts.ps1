#==================================================================================
# Script: 	Ping-Hosts.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	ICMP Ping Check for Hosts return all as Property Bags
#==================================================================================

# Get the named parameters
Param(
    [string]$vCenterName, 
    [string]$UserName, 
    [string]$Password, 
    [string]$Debug,
	[double]$PingTimeout
)

# Get Start Time For Script
$StartTime = (GET-DATE)

#Constants used for event logging
$SCRIPT_NAME			= 'Ping-Hosts.ps1'
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
$PingHosts = {
    Param(
        [string]$vCenterName, 
        [string]$UserName, 
        [string]$Password, 
        [string]$Debug,
		[double]$PingTimeout
    )   

    #Constants used for event logging
    $SCRIPT_NAME			= 'Ping-Hosts.ps1'
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

			# Get List of Hosts
			$HostViews = Get-View -Server $vc -ViewType HostSystem -Property Name
			Foreach ($HostView in $HostViews) {


				# Perform Ping Test
				[int]$timeout = $PingTimeout * 1000
				[switch]$resolve = $true
				[int]$TTL = 128
				[switch]$DontFragment = $false
				[int]$buffersize = 32
				$options = new-object system.net.networkinformation.pingoptions
				$options.TTL = $TTL
				$options.DontFragment = $DontFragment
			    $buffer=([system.text.encoding]::ASCII).getbytes("a"*$buffersize)  
				
				$PingResult = $false
				$ping = New-Object System.Net.NetworkInformation.Ping
				For ($i=1;$i -le 3;$i++) {
					Try {
						$reply = $ping.Send($HostView.Name, $timeout, $buffer, $options)
						If ($reply.Status -eq "Success") {
							$PingResult = $true
						}
					} Catch {
						Continue
					}
				}
				

			    # Create Host Object
				$hostObject = [PSCustomObject]@{
					HostKey = [string]$HostView.MoRef.ToString()
					HostName = [string]$HostView.Name
					PingResult = [string]$PingResult.ToString()
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
	# Start The Job
	Start-Job -Name "PingHost" -ScriptBlock $PingHosts -ArgumentList $vCenterName, $UserName, $Password, $Debug, $PingTimeout | Out-Null

	# Wait For Job
	Wait-Job -Name "PingHost" | Out-Null

	# Get Results from Job
	$Results = Receive-Job -Name "PingHost"

	# Remove Job
	Remove-Job -Name "PingHost"

	# Loop Through Results
	Foreach ($result in $Results) {

		# Test Ping for Host

		# If Result Contains a Property called DatastoreKey
		If ([bool]($result.PSobject.Properties.name -match "HostKey")) {
			$bag = $api.CreatePropertyBag()
			$bag.AddValue("HostKey", $result.HostKey)
			$bag.AddValue("HostName", $result.HostName)
			$bag.AddValue("PingResult", $result.PingResult)
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
