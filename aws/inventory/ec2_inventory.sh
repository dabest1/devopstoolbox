#!/bin/bash

# Purpose:
#     Maintain a local inventory of AWS EC2 instances.
# Usage:
#     Run script with --help option to get usage.

version="1.0.8"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"
config_path="$script_dir/${script_name/.sh/.cfg}"
data_path="$script_dir/${script_name/.sh/.dat}"
data_tmp_path="$script_dir/${script_name/.sh/.dat.tmp}"

# Load configuration settings.
source "$config_path"

# Header row.
header_row="account	name	instance_id	private_ip	region	type	state"

function usage {
    echo "Usage:"
    echo "    $script_name --refresh|[--list [--grep 'regex']]"
    echo
    echo "Description:"
    echo "    -r, --refresh    Refreshes the list of EC2 instances and their state."
    echo "    -l, --list       Displays cached list of EC2 instances and runs refresh afterwards. If no options are supplied, then this option is chosen by default."
    echo "    -g, --grep       Limits output to the regex provided."
    echo "    -h, --help       Displays this help."
    exit 1
}

refresh() {
    script_count=$(ps | grep "$script_name" | grep -v grep | wc -l)
    if [[ $script_count -le 2 ]]; then
        refresh_subtask &> "$log" &
    else
        echo "Warning: Refresh already in progress." 1>&2
    fi
}

refresh_subtask() {
    echo "Start refresh."
    failures=0

    echo "$header_row" > "$data_tmp_path"

    for profile in $profiles; do
        echo "profile: $profile"
        name='*'
        instance_ids=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
        if [[ -z $instance_ids ]]; then
            exit 1
        fi

        aws --profile "$profile" ec2 describe-instances --instance-ids $instance_ids --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, PrivateIpAddress, Placement.AvailabilityZone, InstanceType, State.Name]' --output text | sort | awk -v profile="$profile" '{print profile"\t"$0}' >> "$data_tmp_path"
        rc="$?"
        if [[ $rc -gt 0 ]]; then
            failures=$((failures + 1))
        fi
    done

    if [[ $failures -eq 0 ]]; then
        mv "$data_tmp_path" "$data_path"
        echo "Done."
    else
        echo "Warning: Refresh had some problems." 1>&2
    fi
}

list() {
    wait

    if [[ -z $regex ]]; then
        cat "$data_path"
    else
        echo "$header_row"
        cat "$data_path" | sed '1d' | grep "$regex"
    fi
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
        ;;
    -r|--refresh)
        tasks="$tasks refresh"
        shift
        ;;
    -l|--list)
        tasks="$tasks list"
        shift
        ;;
    -g|--grep)
        shift
        regex="$1"
        shift
        ;;
    *)
        usage
    esac
done

# Remove leading space.
tasks="$(echo "${tasks}" | sed -e 's/^[[:space:]]*//')"

if [[ $tasks == "list" || -z $tasks ]]; then
    tasks="list refresh"
fi

for task in $tasks; do
    case $task in
    refresh)
        refresh
        ;;
    list)
        list
        ;;
    esac
done
