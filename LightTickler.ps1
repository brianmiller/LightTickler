###############################################################################
# * Changes the color of a HomeAssistant light if a Zoom meeting is running.
# * Changes color based on conditions, e.g., Zoom, Zoom+Valheim, etc...
# * Mirrors a related light when a Zoom meeting isn't running.
#
# Written and maintained by:
#  * Brian Miller (brian@phospher.com) 
#  * Jeremy Hargrove (jeremy.hargrove@gmail.com)
###############################################################################

###################
# BEGIN: Contants
###################
#HomeAssistant URL
$HA_URL = "http://37648-homeassistant1.phospher.com:8123"
#HomeAssistant Long Lived Token
$HA_TOKEN = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiIyNzRmMDJmNjE4NTc0ZDllOWE0ZDFhMGExNmNiZGI5ZSIsImlhdCI6MTYxNDg5NjE4NywiZXhwIjoxOTMwMjU2MTg3fQ.oyGxzHE2tpNejNIoWuLRIHd3nEh7CcNRmKDPwbRIjNw"
#Source light that we will mirror when our main condtions are not met
$SOURCE_LIGHT = "light.hallway_1"
#Destination status light that we are manipulating when our main conditions are met
$DESTINATION_LIGHT = "light.hallway_3"
#Full path to SoundVolumeView.exe (download from: https://www.nirsoft.net/utils/soundvolumeview-x64.zip)
$SOUNDVOLUMEVIEW = "C:\Users\brian\Downloads\SoundVolumeView.exe"
###################
# END: Contants
###################


#HTTP auth header being sent to HomeAssistant
$headers = @{"Authorization" = "Bearer $HA_TOKEN"}


###################
# BEGIN: Functions
###################
#Get the current state of the light we're mirroring when a meeting isn't running.
function GET_LIGHT_STATE () {
	#Get current state of light (all JSON)
	$Global:CURRENT_JSON = (Invoke-RestMethod -ContentType "application/json" -Uri $HA_URL/api/states/$SOURCE_LIGHT -Method GET -Headers $headers)
	
	#Get current power state
	$Global:CURRENT_POWER = (Invoke-RestMethod -ContentType "application/json" -Uri $HA_URL/api/states/$SOURCE_LIGHT -Method GET -Headers $headers|select -expand state) 
	
	#Get current color state
	if($CURRENT_POWER -eq "on") {
		#If the light is on, check to see if it's in "rgb_color" mode
		Invoke-RestMethod -ContentType "application/json" -Uri $HA_URL/api/states/$SOURCE_LIGHT -Method GET -Headers $headers|findstr "rgb_color" 2>&1 > $null
		if ($?) {
			#If the light is on AND in "rgb_color" mode, capture the current rgb color code
			$Global:CURRENT_COLOR = ($CURRENT_JSON.psobject.properties.value|findstr "rgb_color").replace(' ','').replace('rgb_color:','').replace('{','[ ').replace('}',' ]').replace(',',', ')
		} else {
			#If the light is on AND NOT in "rgb_color" mode, set color state to soft white
			$Global:CURRENT_COLOR = "[ 255, 205, 120 ]"
		}
		#If the light is on, capture level of brightness
		$Global:CURRENT_BRIGHTNESS = ($CURRENT_JSON.psobject.properties.value|findstr "brightness").replace(' ','').replace('brightness:','')
	}	
}
###################
# END: Functions
###################


###################
# BEGIN: Main
###################
while($true) {
	
	#Save the CPU
	sleep 1
	
	#Is there an active Zoom running?  We use SoundVolumeView.exe to determine if a Zoom meeting is active
	& $SOUNDVOLUMEVIEW /stab "" | .\GetNir "."|findstr /I "Zoom"|findstr /I "Capture" 2>&1 > $null
	$ZOOM_RESULT=$?
	
	#Is Valheim running?
	Get-Process valheim 2>$1 > $null
	$VALHEIM_RESULT=$?
	
	#Always check current state of light to be mirrored
	GET_LIGHT_STATE

	#Main contional evaluation
	if($ZOOM_RESULT -And $VALHEIM_RESULT) {
		echo "A Zoom meeting and Valheim are running..."
		#If Valheim AND a Zoom session are running, set status light to blue
		$JSON = '{"entity_id": "'+$DESTINATION_LIGHT+'", "brightness": 255,"rgb_color": [ 0, 0, 255 ] }'
		Invoke-RestMethod -ContentType "application/json" -Uri $HA_URL/api/services/light/turn_on -Method POST -Headers $headers -Body $JSON 2>&1 > $null
		
	} elseif($ZOOM_RESULT) {
		#If a Zoom meeting is running, set status light to red
		echo "A Zoom meeting is running..."
		$JSON = '{"entity_id": "'+$DESTINATION_LIGHT+'", "brightness": 255,"rgb_color": [ 255, 0, 0 ] }'
		Invoke-RestMethod -ContentType "application/json" -Uri $HA_URL/api/services/light/turn_on -Method POST -Headers $headers -Body $JSON 2>&1 > $null
		
		
	} else {
		#If a Zoom meeting is NOT running and the light to be mirrored is on, mirror the source light with our status light
		echo "A Zoom meeting is not running..."		
		if ($CURRENT_POWER -eq "on") {
			#If the rest of the hallway is on, set the target light state to match the rest of the hallway.
			$JSON = '{"entity_id": "'+$DESTINATION_LIGHT+'", "brightness": '+$CURRENT_BRIGHTNESS+',"rgb_color": '+$CURRENT_COLOR+'}'
			Invoke-RestMethod -ContentType "application/json" -Uri $HA_URL/api/services/light/turn_on -Method POST -Headers $headers -Body $JSON 2>&1 > $null	
		} else {
			#If the rest of the hallway is off, turn off the target light.
			$JSON = '{"entity_id": "'+$DESTINATION_LIGHT+'"}'
			Invoke-RestMethod -ContentType "application/json" -Uri $HA_URL/api/services/light/turn_off -Method POST -Headers $headers -Body $JSON 2>&1 > $null
	    }
	}
}
###################
# END: Main
###################