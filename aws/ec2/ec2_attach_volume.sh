#!/bin/bash

# Purpose:
#     Attach volume to AWS EC2 instance.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

instance_id="$1"
volume_id="$2"
device="$3"
profile="${AWS_PROFILE:-default}"

if [[ $1 == "--help" || -z $1 || -z $2 || -z $3 ]]; then
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name instance_id volume_id device"
    echo
    echo "Example:"
    echo "    $script_name i-abcd1234 vol-abcd1234 /dev/sdf"
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo | tee -a $log

result="$(aws --profile "$profile" ec2 attach-volume --volume-id "$volume_id" --instance-id "$instance_id" --device "$device")"
rc=$?
echo "$result" | tee -a $log
if [[ $rc != 0 ]]; then
    echo "Error: Failed to attach volume." | tee -a $log
    exit 1
fi
