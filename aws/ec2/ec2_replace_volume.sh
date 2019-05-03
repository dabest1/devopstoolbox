#!/bin/bash

# Purpose:
#     Replace existing ec2 volume with a different sized volume.
#     Note that data will be lost on the replaced volume.
# Usage:
#     Run script with -h option to get usage.

version=1.0.0

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

name="$1"
volume_mount="$2"
new_volume_size="$3"
new_volume_type="$4"
profile="${AWS_PROFILE:-default}"

if [[ -z $name || -z $volume_mount || -z $new_volume_size || -z $new_volume_type || $1 == '-h' ]]; then
    echo 'Usage:'
    echo '    export AWS_PROFILE=profile'
    echo "    $script_name hostname volume_mount new_volume_size_GiB new_volume_type"
    echo 'Example:'
    echo "    $script_name my_host /data 1024 gp2"
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo "hostname: $name" | tee -a $log
echo "volume_mount: $volume_mount" | tee -a $log
echo "new_volume_size_GiB: $new_volume_size" | tee -a $log
echo "new_volume_type: $new_volume_type" | tee -a $log
echo | tee -a $log

df=$(ssh "$name" "df -h")
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Could not connect or find such volume."
    exit 1
fi
echo "$df"
mount_df=$(echo "$df" | grep "$volume_mount")
if ! echo "$mount_df" | grep -q "$volume_mount"; then
    echo "Error: Could not find mount."
    exit 1
fi
device=$(echo "$mount_df" | tail -1 | awk '{print $1}')
device_short="${device: -1}"
size=$(echo "$mount_df" | tail -1 | awk '{print $1}')
echo

mount_stat=$(ssh "$name" "stat $volume_mount | grep Access | head -1")
mount_privs=$(echo "$mount_stat" | awk -F'Access:|Uid:|Gid:' '{print $2}' | tr -d ' ()' | awk -F'/' '{print $1}')
mount_owner=$(echo "$mount_stat" | awk -F'Access:|Uid:|Gid:' '{print $3}' | tr -d ' ()' | awk -F'/' '{print $1}')
mount_group=$(echo "$mount_stat" | awk -F'Access:|Uid:|Gid:' '{print $4}' | tr -d ' ()' | awk -F'/' '{print $1}')
echo "$mount_stat"
echo "$mount_df"
echo

instance_id=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
volumes=$(aws --profile "$profile" ec2 describe-volumes --filters "Name=attachment.instance-id, Values=$instance_id" --query 'Volumes[*].{VolumeId:VolumeId,InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,DeleteOnTermination:Attachments[0].DeleteOnTermination,Device:Attachments[0].Device,Size:Size}' --output text)
echo "DeleteOnTermination Device InstanceId Size State VolumeId"
echo "$volumes"
volume_to_delete=$(echo "$volumes" | egrep "/dev/sd${device_short}|/dev/xvd${device_short}" | awk '{print $6}')
device_aws=$(echo "$volumes" | egrep "/dev/sd${device_short}|/dev/xvd${device_short}" | awk '{print $2}')
echo
echo "volume_to_delete: $volume_to_delete"
echo "device_aws: $device_aws"
echo

echo -n 'Are you sure that you want this volume replaced (data will be lost)? y/n: '
read yn
if [[ $yn != y ]]; then
    echo 'Aborted!' | tee -a $log
    exit 1
fi
echo

echo "Unmount and delete old volume..."
./ec2_delete_volume.sh "$volume_to_delete"
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Could not delete volume."
    exit 1
fi
echo
echo

echo "Create new volume..."
./ec2_create_volume.sh "$name" "$new_volume_size" "$new_volume_type" "$device_aws"
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Could not create volume."
    exit 1
fi
echo

echo "Format new volume..."
ssh "$name" "sudo mkfs.ext4 $device"
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Could not format volume."
    exit 1
fi
echo

echo "Mount new volume..."
ssh "$name" "sudo mount -a"
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Could not mount volume."
    exit 1
fi

echo "Set permissions and ownership..."
ssh "$name" "sudo chown '$mount_owner':'$mount_group' '$volume_mount'; sudo chmod '$mount_privs' '$volume_mount'"
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Could not set permissions or ownership."
    exit 1
fi