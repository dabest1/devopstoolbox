#!/bin/bash
################################################################################
# Purpose:
#     Maintain a local inventory of AWS EC2 instances.
# Usage:
#     Run script with --help option to get usage.
################################################################################

version="1.5.2"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"
log_old="$script_dir/${script_name/.sh/.log.old}"
config_path="$script_dir/${script_name/.sh/.cfg}"
data_path="$script_dir/${script_name/.sh/.dat}"
data_tmp_path="$script_dir/${script_name/.sh/.dat.tmp}"
data_old_path="$script_dir/${script_name/.sh/.dat.old}"

# Load configuration settings.
source "$config_path"

# Header row.
header_row="Profile Name    InstanceId  PrivateIp   PublicIp    KeyName AZ  Type    State"

function usage {
    echo "Usage:"
    echo "    $script_name --refresh|[--list [--grep 'regex']]"
    echo
    echo "Description:"
    echo "    -r, --refresh    Refreshes the list of EC2 instances and their state."
    echo "    -l, --list       Displays cached list of EC2 instances. If no options are supplied, then this option is chosen by default."
    echo "    -g, --grep       Limits output to the regex provided."
    echo "    -h, --help       Display this help."
    exit 1
}

refresh() {
    script_count="$(ps | grep "$script_name" | grep -v grep | wc -l)"
    if [[ "$script_count" -le 2 ]]; then
        mv "$log" "$log_old"
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
        aws --profile "$profile" ec2 describe-instances --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, PrivateIpAddress, PublicIpAddress, KeyName, Placement.AvailabilityZone, InstanceType, State.Name]' --output text | sort | awk -v profile="$profile" '{print profile"\t"$0}' >> "$data_tmp_path"
        rc="$?"
        if [[ $rc -gt 0 ]]; then
            failures=$((failures + 1))
        fi
    done

    if [[ $failures -eq 0 ]]; then
        mv "$data_path" "$data_old_path"
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
        (
            echo "$header_row"
            cat "$data_path" | sed '1d' | egrep -- "$regex"
        ) | column -t | egrep --context=1000000 --colour=always -- "$regex"
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

if [[ -z $tasks ]]; then
    tasks="list"
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
