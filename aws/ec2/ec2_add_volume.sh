#!/bin/bash

# Purpose:
#     Add volume to ec2 instance (create and mount volume).
# Usage:
#     Run script with --help option to get usage.

version="1.0.6"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

name="$1"
volume_mount="$2"
volume_size="$3"
volume_type="$4"
device_aws="$5"
mount_privs="$6"
mount_owner="$7"
mount_group="$8"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name hostname volume_mount volume_size_GiB volume_type device mount_privs mount_owner mount_group"
    echo
    echo "Example:"
    echo "    $script_name my_host /data 1024 gp2 /dev/sdf 770 myuser mygroup"
    exit 1
}

if [[ $1 == "--help" || -z $name || -z $volume_mount || -z $volume_size || -z $volume_type || -z $device_aws || -z $mount_privs || -z $mount_owner || -z $mount_group ]]; then
    usage
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo "hostname: $name" | tee -a $log
echo "volume_mount: $volume_mount" | tee -a $log
echo "volume_size_GiB: $volume_size" | tee -a $log
echo "volume_type: $volume_type" | tee -a $log
echo "device: $device_aws" | tee -a $log
echo "mount_privs: $mount_privs" | tee -a $log
echo "mount_owner: $mount_owner" | tee -a $log
echo "mount_group: $mount_group" | tee -a $log
echo | tee -a $log

echo -n 'Are you sure that you want to add a volume? y/n: '
read yn
if [[ $yn != y ]]; then
    echo 'Aborted!' | tee -a $log
    exit 1
fi
echo

echo "Create new volume..."
./ec2_create_volume.sh "$name" "$volume_size" "$volume_type" "$device_aws"
rc=$?
if [[ $rc -ne 0 ]]; then
    echo "Error: Could not create volume."
    exit 1
fi
echo "Done."
echo

echo "Format new volume..."
ssh "$name" "sudo mkfs.ext4 $device_aws"
rc=$?
if [[ $rc -ne 0 ]]; then
    echo "Error: Could not format volume."
    exit 1
fi
echo "Done."
echo

echo "Create mount directory..."
ssh "$name" sudo bash << HERE_DOCUMENT
if [[ ! -d $volume_mount ]]; then
    mkdir "$volume_mount"
fi
if [[ ! -z "\$(ls -A "$volume_mount")" ]]; then
    false
fi
HERE_DOCUMENT
rc=$?
if [[ $rc -ne 0 ]]; then
    echo "Error: Could not create mount directory or existing directory is not empty."
    exit 1
fi
echo "Done."
echo

echo "Mount new volume..."
ssh "$name" "echo '$device_aws $volume_mount auto defaults,auto,noatime 0 0' | sudo tee -a /etc/fstab > /dev/null; sudo mount $volume_mount"
rc=$?
if [[ $rc -ne 0 ]]; then
    echo "Error: Could not mount volume."
    exit 1
fi
echo "Done."
echo

echo "Set permissions and ownership..."
ssh "$name" "sudo chown '$mount_owner':'$mount_group' '$volume_mount'; sudo chmod '$mount_privs' '$volume_mount'"
rc=$?
if [[ $rc -ne 0 ]]; then
    echo "Error: Could not set permissions or ownership."
    exit 1
fi
echo "Done."
