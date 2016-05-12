#!/bin/bash

# Purpose:
#    Create AWS volume and attach it.
# Usage:
#     Run script with no options to get usage.

version=1.0.0

name="$1"
volume_size="$2"
device="$3"
log='create_volume.log'
profile="$AWS_PROFILE"

set -o pipefail
if [[ -z $name || -z $volume_size || -z $device ]]; then
    echo 'Usage:'
    echo '    script.sh hostname volume_size_mb device'
    echo 'Example:'
    echo '    script.sh my_host 1024 /dev/sdf'
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "hostname: $name" | tee -a $log
echo "volume_size_mb: $volume_size" | tee -a $log
echo "device: $device" | tee -a $log
echo | tee -a $log

instance_id=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)

result=$(aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id")
availability_zone=$(echo "$result" | awk -F'"' '/"AvailabilityZone":/{print $4}')

echo 'Create volume...' | tee -a $log
result=$(aws --profile "$profile" ec2 create-volume --size "$volume_size" --availability-zone "$availability_zone")
echo "$result" | tee -a $log
volume_id=$(echo "$result" | awk -F'"' '/"VolumeId":/{print $4}')
state=""
while [[ $state != 'available' ]]; do
    result=$(aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --output json)
    state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
    echo -n "."
    sleep 1
done
echo 'Done.' | tee -a $log

echo 'Attach volume...' | tee -a $log
aws --profile "$profile" ec2 attach-volume --volume-id "$volume_id" --instance-id "$instance_id" --device "$device" | tee -a $log
attachment_state=""
while [[ $attachment_state != 'attached' ]]; do
    result=$(aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --query 'Volumes[*].{State:Attachments[0].State}' --output json)
    attachment_state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
    echo -n "."
    sleep 1
done
echo 'Done.' | tee -a $log
