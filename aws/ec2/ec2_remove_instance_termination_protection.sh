#!/bin/bash

# Purpose:
#     Remove AWS EC2 instance termination protection.
# Usage:
#     Run script with --help option to get usage.

version="1.0.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name {name | instance_id}"
    exit 1
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
        ;;
    *)
        name="$1"
        shift
    esac
done
profile="${AWS_PROFILE:-default}"

if [[ -z $name ]]; then
    usage
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
if echo "$name" | grep -q '^i-'; then
    instance_id="$name"
else
    echo "name: $name" >> $log
    instance_id=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
fi
echo "instance_id: $instance_id" >> $log
if [[ -z $instance_id ]]; then
    echo "Error."
    exit 1
fi

aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, Placement.AvailabilityZone, InstanceType, State.Name]' --output table

echo "Remove termination protection..." | tee -a $log
aws --profile "$profile" ec2 modify-instance-attribute --instance-id "$instance_id" --no-disable-api-termination --output table | tee -a $log
echo 'Done.' | tee -a $log
