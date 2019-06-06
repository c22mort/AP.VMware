#==================================================================================
# Script: 	Get-VirtualCenterInfo.ps1
# Date:		13/12/18
# Author: 	Andi Patrick
# Purpose:	Gets Info from Virtual Centre, returns Property Bag
#==================================================================================

# Get the named parameters
Param(
    [string]$vCenterName, 
    [string]$Debug,
	[double]$PingTimeout
)

# Get Start Time For Script
$StartTime = (GET-DATE)

#Constants used for event logging
$SCRIPT_NAME			= 'Get-VirtualCenterInfo.ps1'
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
if ($Debug -eq $true) { 
    $message = "Script Started for, " + $vCenterName
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_STARTED,$EVENT_LEVEL_INFO, $message) 
} 

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
			$reply = $ping.Send($vCenterName, $timeout, $buffer, $options)
			If ($reply.Status -eq "Success") {
				$PingResult = $true
			}
		} Catch {
			Continue
		}
	}
	# Perform Defaul WebPage Test
	Try {
		$WebResponse = Invoke-WebRequest "https://$vCenterName"
		If ($WebResponse.StatusDescription.ToString().ToLower() -eq "ok") {
			$WebPageTest = $true
		} else {
			$WebPageTest = $false
		}
	} Catch {
	    $message = "Error Getting vSphere Client Page for, " + $vCenterName + "`r`n" + $_
		$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR, $message) 
		$WebPageTest = $false
	}

	# Perform WebClient Test
	Try {
		$WebResponse = Invoke-WebRequest "https://$vCenterName/vsphere-client"
		If ($WebResponse.StatusDescription.ToString().ToLower() -eq "ok") {
			$WebClientTest = $true
		} else {
			$WebClientTest = $false
		}
	} Catch {
	    $message = "Error Getting vSphere Client Page for, " + $vCenterName + "`r`n" + $_
		$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ERROR,$EVENT_LEVEL_ERROR, $message) 
		$WebClientTest = $false
	}

	if ($Debug -eq $true) {
	    $message = "Checked the following for, " + $vCenterName + "`r`n" + "Ping Test : " + $PingResult  + "`r`n" + "Web Page Test : " + $WebPageTest + "`r`n" + "Web Client Test : " + $WebClientTest 
		$api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_EVENT,$EVENT_LEVEL_INFO, $message) 
	}

	# Create Property Bag
	$bag = $api.CreatePropertyBag()
	$bag.AddValue("VirtualCenterName", $vCenterName)
	$bag.AddValue("PingTest", $PingResult)
	$bag.AddValue("WebPageTest", $WebPageTest)
	$bag.AddValue("WebClientTest", $WebClientTest)
	#$api.Return($bag)
	$bag	

# Log Finished Message
if ($Debug -eq $true) {
	# Get End Time For Script
	$EndTime = (GET-DATE)
	$TimeTaken = NEW-TIMESPAN -Start $StartTime -End $EndTime
	$Seconds = [math]::Round($TimeTaken.TotalSeconds, 2)
	# Display Message
    $message = "Script Finished for, " + $vCenterName + ". Took $Seconds Seconds to Complete!"
    $api.LogScriptEvent($SCRIPT_NAME,$SCRIPT_ENDED,$EVENT_LEVEL_INFO, $message) 
}