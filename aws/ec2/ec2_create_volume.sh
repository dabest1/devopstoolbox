#!/bin/bash

# Purpose:
#     Create AWS volume and attach it.
#     If mount point is provided, then format and mount the volume.
# Usage:
#     Run script with --help option to get usage.

version="1.0.8"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

name="$1"
volume_size="$2"
volume_type="$3"
device="$4"
volume_mount="$5"
profile="${AWS_PROFILE:-default}"

if [[ $1 == "--help" || -z $name || -z $volume_size || -z $volume_type || -z $device ]]; then
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name hostname volume_size_GiB volume_type device [volume_mount]"
    echo
    echo "Example:"
    echo "    $script_name my_host 1024 gp2 /dev/sdf"
    echo "    or"
    echo "    $script_name my_host 1024 gp2 /dev/sdf /data"
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo "hostname: $name" | tee -a $log
echo "volume_size_GiB: $volume_size" | tee -a $log
echo "volume_type: $volume_type" | tee -a $log
echo "device: $device" | tee -a $log
if [[ ! -z $volume_mount ]]; then
    echo "volume_mount: $volume_mount" | tee -a $log
fi
echo | tee -a $log

instance_id=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name,Values=$name" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].[InstanceId]' --output text)
rc=$?
if [[ $rc != 0 ]]; then
    echo "Error: Unable to query AWS." | tee -a $log
    exit 1
fi

result=$(aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id")
rc=$?
if [[ $rc != 0 ]]; then
    echo "Error: Unable to query AWS." | tee -a $log
    exit 1
fi
availability_zone=$(echo "$result" | awk -F'"' '/"AvailabilityZone":/{print $4}')

echo "Create volume..." | tee -a $log
result=$(aws --profile "$profile" ec2 create-volume --size "$volume_size" --availability-zone "$availability_zone" --volume-type "$volume_type")
rc=$?
if [[ $rc != 0 ]]; then
    echo "Error: Unable to create volume." | tee -a $log
    exit 1
fi
echo "$result" | tee -a $log
volume_id=$(echo "$result" | awk -F'"' '/"VolumeId":/{print $4}')
state=""
while [[ $state != "available" ]]; do
    result=$(aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --output json)
    state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
    echo -n "."
    sleep 1
done
echo "Done." | tee -a $log

echo "Attach volume..." | tee -a $log
aws --profile "$profile" ec2 attach-volume --volume-id "$volume_id" --instance-id "$instance_id" --device "$device" | tee -a $log
attachment_state=""
while [[ $attachment_state != "attached" ]]; do
    result=$(aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --query 'Volumes[*].{State:Attachments[0].State}' --output json)
    attachment_state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
    echo -n "."
    sleep 1
done
echo "Done." | tee -a $log

if [[ -z $volume_mount ]]; then
    exit 0
fi

echo | tee -a $log
echo "Format new volume..." | tee -a $log
ssh "$name" "sudo mkfs.ext4 $device" | tee -a $log
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Could not format volume." | tee -a $log
    exit 1
fi
echo "Done." | tee -a $log
echo | tee -a $log

echo "Mount new volume..." | tee -a $log
ssh "$name" "echo '$device $volume_mount ext4 defaults,auto,noatime,noexec 0 0' | sudo tee -a /etc/fstab > /dev/null; sudo mkdir $volume_mount; sudo mount -a" | tee -a $log
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Could not mount volume." | tee -a $log
    exit 1
fi
echo "Done." | tee -a $log
