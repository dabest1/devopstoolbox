#!/bin/bash

# Purpose:
#     Start AWS instance.
# Usage:
#     Run script with --help option to get usage.

version="1.1.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

usage() {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [-n] [-w] {name | instance_id}..."
    echo
    echo "Description:"
    echo "    -n, --no-prompt    No confirmation prompt."
    echo "    -w, --wait         Wait for 'running' state before finishing."
    echo "    -h, --help         Display this help."
    exit 1
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
        ;;
    -n|--no-prompt)
        do_not_prompt="yes"
        shift
        ;;
    -w|--wait)
        wait_for_running="yes"
        shift
        ;;
    *)
        if [[ -z $names ]]; then
            names="$1"
        else
            names="$names $1"
        fi
        shift
    esac
done
profile="${AWS_PROFILE:-default}"

if [[ -z $names ]]; then
    usage
fi

echo >> "$log"
echo >> "$log"
date +'%F %T %z' >> "$log"
echo "profile: $profile" | tee -a "$log"

for name in $names; do
    echo | tee -a "$log"
    if echo "$name" | grep -q '^i-'; then
        instance_id="$name"
    else
        echo "name: $name" | tee -a "$log"
        instance_id=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "Error: Failed to query AWS." | tee -a "$log"
            exit 1
        fi
    fi
    echo "instance_id: $instance_id" | tee -a "$log"

    aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, Placement.AvailabilityZone, InstanceType, State.Name]' --output table
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failed to query AWS." | tee -a "$log"
        exit 1
    fi
    aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --output table >> "$log"

    aws --profile "$profile" ec2 describe-volumes --filters "Name=attachment.instance-id, Values=$instance_id" --query 'Volumes[*].{VolumeId:VolumeId,InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,DeleteOnTermination:Attachments[0].DeleteOnTermination,Device:Attachments[0].Device,Size:Size}' --output table | tee -a "$log"

    if [[ ! $do_not_prompt ]]; then
        echo -n 'Are you sure that you want this instance started? y/n: '
        read -r yn
        if [[ $yn != y ]]; then
            echo 'Aborted!' | tee -a "$log"
            exit 1
        fi
        echo
    fi

    echo "Start instance..." | tee -a "$log"
    aws --profile "$profile" ec2 start-instances --instance-ids "$instance_id" --output table | tee -a "$log"
    state=""
    while [[ $state != "running" ]] && [[ $wait_for_running == yes ]]; do
        state=$(aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[State.Name]' --output text)
        echo -n "."
        sleep 1
    done
    echo 'Done.' | tee -a "$log"
done
