#!/bin/bash

# Purpose:
#     Show MongoDB replica set information.
#     In the future, it will:
#     Show MongoDB replica set or cluster information.
# Usage:
#     Run script with --help option to get usage.

version="1.1.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

user_host_port="$1"

usage() {
    echo "Usage:"
    echo "    $script_name mongodb_node[:port]"
    echo
    echo "Example:"
    echo "    $script_name my_mongodb_host1"
    exit 1
}

if [[ $1 == "--help" || -z $1 ]]; then
    usage
fi

mongod_host="$(echo "$user_host_port" | awk -F: '{print $1}')"
mongod_port="$(echo "$user_host_port" | awk -F: '{print $2}')"
mongod_port="${mongod_port:-27017}"

result="$(mongo --host "$mongod_host:$mongod_port" --quiet --norc --eval 'print(JSON.stringify(rs.status()))')"

# Stand alone MongoDB.
if echo "$result" | grep -q 'ok":0,"errmsg":"not running with --replSet"'; then
	echo "node state"
	echo "$mongod_host:$mongod_port standalone"
# Replica set.
else
	{
		set="$(echo "$result" | jq '.set' | tr -d '"')"
		node_arr=( $(echo "$result" | jq '.members[].name' | tr -d '"') )
		state_arr=( $(echo "$result" | jq '.members[].stateStr' | tr -d '"') )
		uptime_arr=( $(echo "$result" | jq '.members[].uptime' | tr -d '"') )
		optime_t_arr=( $(echo "$result" | jq '.members[].optime."$timestamp".t' | tr -d '"') )
		optime_i_arr=( $(echo "$result" | jq '.members[].optime."$timestamp".i' | tr -d '"') )

		echo "node state replica_set uptime optime"
		for ((i=0; i<${#node_arr[@]}; i++)); do
			echo "${node_arr[$i]} ${state_arr[$i]} $set ${uptime_arr[$i]} ${optime_t_arr[$i]},${optime_i_arr[$i]}"
		done
	} | column -t
fi
