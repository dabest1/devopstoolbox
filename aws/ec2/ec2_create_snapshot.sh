#!/bin/bash

# Purpose:
#     Create AWS snapshot.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

profile="${AWS_PROFILE:-default}"
volume_id="$1"
snapshot_descr="$2"

if [[ $1 == "--help" || -z $volume_id ]]; then
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name volume-id \"snapsho-description\""
    echo
    echo "Example:"
    echo "    $script_name vol-0123456789abcdef0"
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo "volume_id: $volume_id" | tee -a $log
echo | tee -a $log

aws --profile "$profile" ec2 create-snapshot --volume-id "$volume_id" --description "$snapshot_descr"
if [[ $? != 0 ]]; then
    echo "Error: Unable to create snapshot." | tee -a $log
    exit 1
fi
