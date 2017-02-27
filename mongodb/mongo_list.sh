#!/bin/bash

# Purpose:
#     Show MongoDB replica set information.
#     In the future, it will:
#     Show MongoDB replica set or cluster information.
# Usage:
#     Run script with --help option to get usage.

version="1.0.1"

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

user_host_prefix="$(echo "$user_host_port" | awk -F: '{print $1}' | sed -e 's/-.$/-/')"
user_port="$(echo "$user_host_port" | awk -F: '{print $2}')"
user_port="${user_port:-27017}"
mongod_host_port_1="${user_host_prefix}1:$user_port"
mongod_host_port_2="${user_host_prefix}2:$user_port"
mongod_host_port_3="${user_host_prefix}3:$user_port"

echo "set  node  state"
mongod_host="$(echo $mongod_host_port_1 | awk -F: '{print $1}')"
mongod_port="$(echo $mongod_host_port_1 | awk -F: '{print $2}')"

result="$(mongo --host "$user_host_port" --quiet --norc --eval 'print(JSON.stringify(rs.status()))')"

# Stand alone MongoDB.
if echo "$result" | grep -q 'ok":0,"errmsg":"not running with --replSet"'; then
		echo "none  $user_host_port  standalone"
# Replica set.
else
	node="$(echo "$result" | jq ".members[] | select(.name == \"$mongod_host_port_1\")")"
	state_str="$(echo "$node" | jq '.stateStr' | tr -d '"')"
	set="$(echo "$result" | jq '.set' | tr -d '"')"
	echo "$set	$mongod_host_port_1	$state_str"

	node="$(echo "$result" | jq ".members[] | select(.name == \"$mongod_host_port_2\")")"
	state_str="$(echo "$node" | jq '.stateStr' | tr -d '"')"
	echo "$set	$mongod_host_port_2	$state_str"

	node="$(echo "$result" | jq ".members[] | select(.name == \"$mongod_host_port_3\")")"
	state_str="$(echo "$node" | jq '.stateStr' | tr -d '"')"
	echo "$set	$mongod_host_port_3	$state_str"
fi
