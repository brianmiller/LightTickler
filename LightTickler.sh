#!/bin/bash

###############################################################################
# * Changes the color of a HomeAssistant light if a Zoom meeting is running.
# * Changes color based on conditions, e.g., Zoom, Zoom+Valheim, etc...
# * Mirrors a related light when a Zoom meeting isn't running.
#
# Written and maintained by:
#  * Brian Miller (brian@phospher.com) 
#  * Jeremy Hargrove (jeremy.hargrove@gmail.com)
###############################################################################


##Constants
#HomeAssistant Long Lived Token
HA_TOKEN=""
#HomeAssistant URL
HA_URL=""
#Camera device
CAMERA=/dev/video0


###################
# BEGIN: Functions
###################
#$1=entity, $2=action (turn_on, turn_off)
function HA_SCENE_POST() {
	curl -X POST \
         -H "Authorization: Bearer $HA_TOKEN" \
         -H "Content-Type: application/json" \
         -d "{\"entity_id\": \"$1\"}" \
         $HA_URL/api/services/scene/$2

}

#$1=json, $2=API
function POST_TO_API() {
	curl -X POST \
         -H "Authorization: Bearer $HA_TOKEN" \
         -H "Content-Type: application/json" \
	 -d "$1" \
         $HA_URL/api/$2

}

#$1=entity
function GET_LIGHT_STATE() {
	CURRENT_POWER=$(curl -s -X GET -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" $HA_URL/api/states/$1|jq "."|grep "state"|tr -s " "|tr -d '\n'|sed 's/.$//'|cut -d "\"" -f4)
	CURRENT_COLOR=$(curl -s -X GET -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" $HA_URL/api/states/$1|jq "."|grep -A 4 "rgb_color"|tr -s " "|tr -d '\n'|sed 's/.$//')
	CURRENT_BRIGHTNESS=$(curl -s -X GET -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" $HA_URL/api/states/$1|jq "."|grep "brightness"|tr -s " "|tr -d '\n'|sed 's/.$//')

	if [ "$CURRENT_COLOR" = "" ]; then
		#If for some reason the output JSON is missing RBG values, set it to the default Soft White from Philips Hue.
		CURRENT_COLOR="\"rgb_color\": [ 255, 205, 120 ]"
	fi

}


###################
# END: Functions
###################


###################
# BEGIN: Main
###################
PID=$$
ps -ef|grep ZoomIndicator.sh|grep -v grep|grep -v $PID|grep ZoomIndicator.sh > /dev/null 2>&1
if [ "$?" = "0" ]; then
	echo "ERROR: ZoomIndicator.sh is already running...."
	exit 1
fi


while [ 1 = 1 ]; do
	
	#Save the CPU
	sleep 1

	#Is Zoom running?  We check PulseAudio (Linux) for active Zoom audio streams.
	pactl list sink-inputs|grep -i "sink-input-by-application-name:ZOOM VoiceEngine" > /dev/null 2>&1
	#pacmd list-sink-inputs|grep "ZOOM VoiceEngine" > /dev/null 2>&1
	ZOOM_RESULT=$?

	#Is the Camera on?
	fuser $CAMERA 2>/dev/null
	CAMERA_RESULT=$?

	#Is Valheim running?
	ps -ef|grep -v grep|grep valheim.x86_64 > /dev/null 2>&1
	VALHEIM_RESULT=$?

	#Get current state of a light in the same group the light we're manipulating during a Zoom call.  
	#This state is used to revert the light back to the original state that existed before the Zoom meeting.
	GET_LIGHT_STATE light.hallway_1

	#If Zoom is running, do something, else do something.
	if [ -f "/tmp/red" ]; then
		echo "Manual setting detected '/tmp/red' exists..."
		POST_TO_API '{"entity_id": "light.hallway_3", "brightness": 255, "rgb_color": [ 255, 0, 0 ]}' 'services/light/turn_on'
	elif [ "$ZOOM_RESULT" = 0 ] && [ "$VALHEIM_RESULT" = 0 ]; then
		echo "A Zoom meeting and are Valheim are running..."
		POST_TO_API '{"entity_id": "light.hallway_3", "brightness": 255, "rgb_color": [ 0, 0, 255 ]}' 'services/light/turn_on'
	elif [ "$ZOOM_RESULT" = 0 ]; then
		echo "A Zoom meeting is running..."
		POST_TO_API '{"entity_id": "light.hallway_3", "brightness": 255, "rgb_color": [ 255, 0, 0 ]}' 'services/light/turn_on'
	else
		echo "A Zoom meeting is not running..."
		if [ "$CURRENT_POWER" = "on" ]; then
			#If the rest of the hallway is on, set the target light state to match the rest of the hallway.
			POST_TO_API "{\"entity_id\": \"light.hallway_3\",$CURRENT_BRIGHTNESS,$CURRENT_COLOR}" 'services/light/turn_on'
	
		else
			#If the rest of the hallway is off, turn off the target light.
			POST_TO_API "{\"entity_id\": \"light.hallway_3\"}" 'services/light/turn_off'
		fi	
	fi

done
###################
# END: Main
###################
