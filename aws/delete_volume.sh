#!/bin/bash

# Purpose:
#    Delete AWS Volume.
# Usage:
#     Run script with no options to get usage.

version=1.0.2

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
echo "volume_id: $volume_id" | tee -a $log

aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --output table | tee -a $log
rc=$?
if [[ $rc -ne 0 ]]; then
    echo 'Error getting volume information.'
    exit 1
fi

echo -n 'Are you sure that you want this volume deleted? y/n: '
read yn
if [[ $yn == y ]]; then
    result=$(aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --query 'Volumes[*].{InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,Device:Attachments[0].Device}')
    instance_id=$(echo "$result" | awk -F'"' '/"InstanceId":/{print $4}')
    device=$(echo "$result" | awk -F'"' '/"Device":/{print $4}')
    attach_state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
    if [[ $attach_state == 'attached' || $attach_state == 'busy' ]]; then
        name=$(aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0]]' --output text)
        echo 'Unmount volume...'
        ssh "$name" "cmd=\$(cat /etc/fstab | grep '/dev/xvd${device: -1}' | awk '{print \$1}' | xargs echo sudo umount); echo \$cmd; eval \$cmd"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo 'Error unmounting volume.'
            exit 1
        fi
        echo 'Detach volume...'
        aws --profile "$profile" ec2 detach-volume --volume-id "$volume_id"
    fi
    echo "Deleting volume_id: $volume_id" | tee -a $log
    aws --profile "$profile" ec2 delete-volume --volume-id "$volume_id" | tee -a $log
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo 'Error deleting volume.'
        exit 1
    fi
    echo 'Done.'
else
    echo 'Aborted!' | tee -a $log
    exit 1
fi
