#!/bin/bash

# Purpose:
#     Maintain a local inventory of AWS EC2 instances.
# Usage:
#     Run script with --help option to get usage.

version=1.0.0

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"
data_path="$script_dir/${script_name/.sh/.dat}"
data_tmp_path="$script_dir/${script_name/.sh/.dat.tmp}"

# Load configuration settings.
source "$config_path"

command=$1

if [[ $1 == '--help' || -z $1 ]]; then
    echo 'Usage:'
    echo "    $script_name refresh|list"
    exit 1
fi

refresh() {
    # Header row.
    echo "account	name	instance_id	region	type	state" > "$data_tmp_path"

    for profile in $profiles; do
        echo "profile: $profile"
        name='*'
        instance_ids=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
        if [[ -z $instance_ids ]]; then
            exit 1
        fi

        aws --profile "$profile" ec2 describe-instances --instance-ids $instance_ids --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, Placement.AvailabilityZone, InstanceType, State.Name]' --output text | sort | awk -v profile="$profile" '{print profile, "\011", $0}' >> "$data_tmp_path"
    done

    mv "$data_tmp_path" "$data_path"
}

list() {
    cat "$data_path"
}

case $command in
refresh)
    refresh
    ;;
list)
    list
    ;;
*)
    exit 1
    ;;
esac
