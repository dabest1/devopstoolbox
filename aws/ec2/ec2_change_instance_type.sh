#!/bin/bash

# Purpose:
#     Change AWS instance type. Instance will be stopped, type changed, and instance started.
# Usage:
#     Run script with --help option to get usage.

version="1.0.3"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

name="$1"
instance_type="$2"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name {name | instance_id} instance_type"
    echo
    echo "Example:"
    echo "    $script_name myhost m3.medium"
    exit 1
}

if [[ $1 == "--help" || -z $name ]]; then
    usage
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
if echo "$name" | grep -q '^i-'; then
    instance_id="$name"
else
    echo "name: $name" | tee -a $log
    instance_id=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
fi
echo "instance_id: $instance_id" | tee -a $log
if [[ -z $instance_id || -z $instance_type ]]; then
    echo "Error."
    exit 1
fi
echo

echo "Stop instance..."
"$script_dir"/ec2_stop_instance.sh -w "$instance_id"
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Instance could not be stopped."
    exit 1
fi
echo

echo "Modify instance type..."
if [[ $instance_type == "m3.medium" ]]; then
    aws --profile "$profile" ec2 modify-instance-attribute --instance-id "$instance_id" --no-ebs-optimized
    rc=$?
fi
aws --profile "$profile" ec2 modify-instance-attribute --instance-id "$instance_id" --instance-type "$instance_type"
rc=$(($? + $rc))
if [[ $rc -gt 0 ]]; then
    echo "Error: Instance type could not be changed."
    exit 1
fi
echo "Done."
echo

echo "Start instance..."
"$script_dir"/ec2_start_instance.sh -w "$instance_id"
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Instance could not be started."
    exit 1
fi
