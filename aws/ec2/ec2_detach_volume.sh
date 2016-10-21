#!/bin/bash

# Purpose:
#     Detach volume from AWS EC2 instance.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

volume_id="$1"
profile="${AWS_PROFILE:-default}"

if [[ $1 == "--help" || -z $1 ]]; then
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name volume_id"
    echo
    echo "Example:"
    echo "    $script_name vol-1234abcd"
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo | tee -a $log

result="$(aws --profile "$profile" ec2 detach-volume --volume-id "$volume_id")"
rc=$?
echo "$result" | tee -a $log
if [[ $rc != 0 ]]; then
    echo "Error: Failed to detach volume." | tee -a $log
    exit 1
fi
