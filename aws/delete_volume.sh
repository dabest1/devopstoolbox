#!/bin/bash

# Purpose:
#    Delete AWS Volume.
# Usage:
#     Run script with no options to get usage.

version=1.0.3

volume_id="$1"
log='delete_volume.log'
profile="$AWS_PROFILE"

set -o pipefail
if [[ -z $volume_id ]]; then
    echo 'Usage:'
    echo '    script.sh volume_id'
    exit 1
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
    attach_state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
    if [[ $attach_state == 'attached' || $attach_state == 'busy' ]]; then
        name=$(aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0]]' --output text)
        echo 'Unmount volume...' | tee -a $log
        ssh "$name" "cmd=\$(cat /etc/fstab | grep '/dev/xvd${device:(-1)}' | awk '{print \$1}' | xargs echo sudo umount); echo \$cmd; eval \$cmd"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo 'Warning: Could not unmount volume.' | tee -a $log
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
