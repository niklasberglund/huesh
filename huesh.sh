#!/bin/sh

config_file_path="$HOME/.hueshconfig"
client_name="huesh-client"

function discover_bridge
{
    discover_response=$(curl -s "https://www.meethue.com/api/nupnp")
    bridge_count=$(printf "$discover_response" | python -c "import json,sys;obj=json.load(sys.stdin);print len(obj);")

    if [ "$bridge_count" == "0" ]
    then
        printf "No Hue bridge found\n"
        exit 1
    fi

    bridge_address=$(printf "$discover_response" | python -c "import json,sys;obj=json.load(sys.stdin);print obj[0]['internalipaddress'];")

    printf "$bridge_address"
}

function authenticate_with_bridge
{
    ip_address="$1"

    response_json=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"devicetype\":\"$client_name\"}" "http://$ip_address/api/")

    has_error=$(printf "$response_json" | python -c "import json,sys;obj=json.load(sys.stdin);print obj[0].has_key('error');")

    if [ "$has_error" == "True" ]
    then
        printf "Failed to get token from Hue bridge at $ip_address.\n"
        exit 1
    else
        token=$(printf "$response_json" | python -c "import json,sys;obj=json.load(sys.stdin);print obj[0]['success']['username'];")
        printf "$token"
    fi
}

function save_config
{
    ip_address="$1"
    token="$2"

    printf "# Persistent storage for huesh.sh Hue bridge credentials\n$ip_address,$token" > "$config_file_path"
}

function get_ip_address
{
    config_line=$(awk 'NR==2' "$config_file_path")
    ip_address=$(printf "$config_line" | cut -d, -f1)
    printf "$ip_address"
}

function get_token
{
    config_line=$(awk 'NR==2' "$config_file_path")
    token=$(printf "$config_line" | cut -d, -f2)
    printf "$token"
}

function send_get_request
{
    bridge_ip_address="$1"
    token="$2"
    endpoint="$3"

    response_json=$(curl -s -H "Content-Type: application/json" "http://$bridge_ip_address/api/$token/$endpoint")

    printf "$response_json"
}

function send_put_request
{
    bridge_ip_address="$1"
    token="$2"
    endpoint="$3"
    data="$4"

    response_json=$(curl -s -X PUT -H "Content-Type: application/json" -d "$data" "http://$bridge_ip_address/api/$token/$endpoint")

    printf "$response_json"
}

function send_state_update_request
{
    light_id="$1"
    data="$2"

    bridge_ip_address=$(get_ip_address)
    token=$(get_token)

    send_put_request "$bridge_ip_address" "$token" "lights/$light_id/state" "$data"
}

function assure_authenticated
{
    token=$(get_token)

    if [ -z "$token" ]
    then
        printf "You must first authenticate by pushing the button on your Hue bridge then run this script and pass \"auth\" argument.\n"
        exit 1
    fi
}


if [ "$1" == "auth" ]
then
    bridge_ip_address=$(discover_bridge)
    token=$(authenticate_with_bridge "$bridge_ip_address")

    printf "IP address: $bridge_ip_address\ntoken: $token\n"

    if [ ! -z "$token" ]
    then
        printf "Successfully discovered and authorized with Hue bridge. Storing credentials in $config_file_path\n"
        save_config "$bridge_ip_address" "$token"
    else
        printf "Found a Hue bridge but can't connect to it. Make sure you push the button on your Hue bridge before running \"auth\"."
        exit 1
    fi
elif [ "$1" == "list-lights" ]
then
    assure_authenticated
    bridge_ip_address=$(get_ip_address)
    token=$(get_token)

    lights_response_json=$(send_get_request "$bridge_ip_address" "$token" "lights")

    formatted_lights_list=$(printf "$lights_response_json" | python -c 'import json,sys;jsonDict=json.load(sys.stdin);
for key in jsonDict: print key + ":" +  jsonDict[key]["name"];')

    printf "$formatted_lights_list\n"

    #printf "$bridge_ip_address $token\n"
    #printf "$lights_response_json\n"
elif [ "$1" == "set-hsl" ]
then
    assure_authenticated
    light_id="$2"
    hue="$3"
    saturation="$4"
    brightness="$5"

    data="{\"on\":true, \"sat\":$saturation, \"bri\":$brightness,\"hue\":$hue}"

    send_state_update_request "$light_id" "$data"
elif [ "$1" == "set-hue" ]
then
    assure_authenticated
    light_id="$2"
    hue="$3"

    data="{\"on\":true, \"hue\":$hue}"

    send_state_update_request "$light_id" "$data"
elif [ "$1" == "set-saturation" ]
then
    assure_authenticated
    light_id="$2"
    saturation="$3"

    data="{\"on\":true, \"sat\":$saturation}"

    send_state_update_request "$light_id" "$data"
elif [ "$1" == "set-brightness" ]
then
    assure_authenticated
    light_id="$2"
    brightness="$5"

    data="{\"on\":true, \"bri\":$brightness}"

    send_state_update_request "$light_id" "$data"
fi
