#!/bin/sh

#> Usage: huesh.sh <command> [<args>]
#>
#> Tool for controlling Hue lights.
#>
#> EXAMPLES:
#>     huesh.sh auth # Authenticates with Hue bridge
#>     huesh.sh list-lights # List all lights in your Hue system
#>     huesh.sh set-brightness 1 20000 # Set brightness level for light with id 1
#>
#> COMMANDS:
#>     help             Prints these usage instructions.
#>     auth             Authenticate with a Hue bridge on the same network. Note that you must push the button on Hue bridge before authenticating.
#>     list-lights      List all Lights in your Hue system.
#>     list-scenes      List all scenes in your Hue system.
#>     set-hsl          Set hue, saturation and brightness for a specific light.
#>     set-hue          Set hue for a specific light.
#>     set-saturation   Set saturation for a specific light.
#>     set-brightness   Set brightness for a specific light.
#>

config_file_path="$HOME/.hueshconfig"
script_path="$0"
client_name="huesh-client"

function print_usage
{
    usage_text=$(sed -n -e '/^#\>/p' "$script_path" | sed 's/^#\>//')
    printf "$usage_text\n\n"
}

function discover_bridge
{
    discover_response=$(curl -s "https://www.meethue.com/api/nupnp")
    bridge_count=$(printf "$discover_response" | python -c "import json,sys;obj=json.load(sys.stdin);print len(obj);")

    if [ "$bridge_count" == "0" ]
    then
        (>&2 printf "No Hue bridge found\n")
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
        (>&2 printf "Failed to get token from Hue bridge at $ip_address.\n")
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
        (>&2 printf "You must first authenticate by pushing the button on your Hue bridge then run this script and pass \"auth\" argument.\n")
        exit 1
    fi
}


while getopts "h" option
do
    case $option in
    h)
        print_usage
        exit 0
        ;;
    \?)
        print_usage
        exit 1
        ;;
    esac
done


if [ "$1" == "help" ]
then
    print_usage
elif [ "$1" == "auth" ]
then
    bridge_ip_address=$(discover_bridge)

    if [ $? == 1 ]
    then
        exit 1
    fi

    token=$(authenticate_with_bridge "$bridge_ip_address")

    printf "IP address: $bridge_ip_address\ntoken: $token\n"

    if [ ! -z "$token" ]
    then
        printf "Successfully discovered and authorized with Hue bridge. Storing credentials in $config_file_path\n"
        save_config "$bridge_ip_address" "$token"
    else
        (>&2 printf "Found a Hue bridge but can't connect to it. Make sure you push the button on your Hue bridge before running \"auth\".")
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
elif [ "$1" == "list-scenes" ]
then
    assure_authenticated
    bridge_ip_address=$(get_ip_address)
    token=$(get_token)

    scenes_response_json=$(send_get_request "$bridge_ip_address" "$token" "scenes")

    formatted_scenes_list=$(printf "$scenes_response_json" | python -c 'import json,sys;jsonDict=json.load(sys.stdin);
for key in jsonDict: print key + ":" +  jsonDict[key]["name"];')

    printf "$formatted_scenes_list\n"
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
elif [ "$1" == "set-on" ]
then
    assure_authenticated
    light_id="$2"
    on_state="$3"

    data="{\"on\":$on_state}"

    send_state_update_request "$light_id" "$data"
fi
