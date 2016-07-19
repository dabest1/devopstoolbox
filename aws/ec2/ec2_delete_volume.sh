#!/bin/bash

# Purpose:
#     Delete AWS Volume.
# Usage:
#     Run script with -h option to get usage.

version=1.0.7

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

function usage {
    echo 'Usage:'
    echo "    $script_name [-i|--ignore] volume_id"
    echo
    echo "Description:"
    echo "    -h, --help    Show this help."
    echo "    -i, --ignore    Ignore unmount error."
    exit 1
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
        ;;
    -i|--ignore)
        ignore_error=yes
        shift
        ;;
    *)
        volume_id="$1"
        shift
    esac
done
profile="${AWS_PROFILE:-default}"

if [[ -z $volume_id ]]; then
    usage
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo "volume_id: $volume_id" | tee -a $log
echo | tee -a $log

aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --output table | tee -a $log
rc=$?
if [[ $rc -ne 0 ]]; then
    echo 'Error getting volume information.' | tee -a $log
    exit 1
fi
result=$(aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --output json)
instance_id=$(echo "$result" | awk -F'"' '/"InstanceId":/{print $4}')
if [[ ! -z $instance_id ]]; then
    aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, Placement.AvailabilityZone, InstanceType, State.Name]' --output table | tee -a $log
fi

echo -n 'Are you sure that you want this volume deleted? y/n: ' | tee -a $log
read yn
if [[ $yn == y ]]; then
    result=$(aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --query 'Volumes[*].{InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,Device:Attachments[0].Device}')
    instance_id=$(echo "$result" | awk -F'"' '/"InstanceId":/{print $4}')
    device=$(echo "$result" | awk -F'"' '/"Device":/{print $4}')
    device_short="${device: -1}"
    attach_state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
    if [[ $attach_state == 'attached' || $attach_state == 'busy' ]]; then
        name=$(aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0]]' --output text)
        echo 'Unmount volume...' | tee -a $log
        ssh "$name" "cmd=\$(cat /etc/fstab | egrep '/dev/sd${device_short}|/dev/xvd${device_short}' | awk '{print \$1}' | xargs echo sudo umount); echo \$cmd; eval \$cmd"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo 'Error: Could not unmount volume.' | tee -a $log
            if [[ $ignore_error != yes ]]; then
                exit 1
            fi
        fi
        echo 'Done.'

        echo 'Detach volume...' | tee -a $log
        aws --profile "$profile" ec2 detach-volume --volume-id "$volume_id" | tee -a $log
        state=""
        while [[ $state != 'available' ]]; do
            result=$(aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --query 'Volumes[*].{State:State}' --output json)
            state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
            echo -n "."
            sleep 1
        done
        echo 'Done.' | tee -a $log
    fi
    echo "Delete volume..." | tee -a $log
    aws --profile "$profile" ec2 delete-volume --volume-id "$volume_id" | tee -a $log
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo 'Error deleting volume.' | tee -a $log
        exit 1
    fi
    echo 'Done.' | tee -a $log
else
    echo 'Aborted!' | tee -a $log
    exit 1
fi
