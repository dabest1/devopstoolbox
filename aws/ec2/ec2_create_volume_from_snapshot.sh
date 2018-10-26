#!/bin/bash

# Purpose:
#     Create AWS volume from snapshot. Optionally attach and mount volume.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

profile="${AWS_PROFILE:-default}"

usage() {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [--profile profile] [--region region] -s snapshot-id -v volume-type {-a availability-zone | {-i {name | instance_id} -d device [-m volume_mount]]}}"
    echo
    echo "Example:"
    echo "    $script_name -s snap-0123456789abcdef0 -v gp2 -a us-east-1a"
    echo "    $script_name -s snap-0123456789abcdef0 -v gp2 -i i-01234567 -d /dev/sdf -m /mnt/new"
    echo
    echo "Description:"
    echo "    -a, --availability-zone    The AWS availability zone, in which the volume will be created."
    echo "    -d, --device               Attach volume to this device name. Should be used with -i option."
    echo "    -i, --instance             Attach volume to this instance name or ID."
    echo "    -m, --mount                Mount point to which the volume will be optionally mounted."
    echo "    -s, --snapshot-id          Snapshot ID from which the volume will be created."
    echo "    -v, --volume-type          Volume type to create: standard, io1, gp2, sc1, or st1."
    echo "    --profile                  Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE variable."
    echo "    --region                   Use a specified region instead of region from configuration or environment setting."
    echo "    -h, --help                 Display this help."
    exit 1
}

while test -n "$1"; do
    case "$1" in
    -a|--availability-zone)
        shift
        availability_zone="$1"
        shift
        ;;
    -d|--device)
        shift
        device="$1"
        shift
        ;;
    -i|--instance)
        shift
        instance="$1"
        shift
        ;;
    -m|--mount)
        shift
        volume_mount="$1"
        shift
        ;;
    --profile)
        shift
        profile="$1"
        shift
        ;;
    --region)
        shift
        region="$1"
        region_opt="--region=$region"
        shift
        ;;
    -s|--snapshot-id)
        shift
        snapshot_id="$1"
        shift
        ;;
    -v|--volume-type)
        shift
        volume_type="$1"
        shift
        ;;
    -h|--help|*)
        usage
        ;;
    esac
done

if [[ -z $snapshot_id || -z $volume_type ]]; then
    echo "ERROR: Snapshot ID and volume type needs to be provided."
    usage
fi

if [[ -z $availability_zone && -z $instance ]]; then
    echo "ERROR: Either availability zone or instance needs to be provided."
    usage
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo "region: $region" | tee -a $log
echo "snapshot_id: $snapshot_id" | tee -a $log
if [[ $availability_zone ]]; then
    echo "availability_zone: $availability_zone" | tee -a $log
fi
if [[ $instance ]]; then
    echo "instance: $instance" | tee -a $log
fi
if [[ $device ]]; then
    echo "device: $device" | tee -a $log
fi
if [[ $volume_mount ]]; then
    echo "volume_mount: $volume_mount" | tee -a $log
fi
echo | tee -a $log

if [[ $instance ]]; then
    if echo "$instance" | grep -q '^i-'; then
        instance_id="$instance"
    else
        instance_id=$(aws --profile "$profile" $region_opt ec2 describe-instances --filters "Name=tag:Name, Values=$instance" --query 'Reservations[].Instances[].[InstanceId]' --output text)
        rc=$?
        if [[ $rc != 0 ]]; then
            echo "Error: Unable to query AWS." | tee -a $log
            exit 1
        fi
    fi

    result=$(aws --profile "$profile" $region_opt ec2 describe-instances --instance-ids "$instance_id" --output json)
    rc=$?
    if [[ $rc != 0 ]]; then
        echo "Error: Unable to query AWS." | tee -a $log
        exit 1
    fi
    availability_zone=$(echo "$result" | awk -F'"' '/"AvailabilityZone":/{print $4}')
fi

echo "Create volume..." | tee -a $log
result=$(aws --profile "$profile" $region_opt ec2 create-volume --snapshot-id "$snapshot_id" --availability-zone "$availability_zone" --volume-type "$volume_type")
rc=$?
if [[ $rc != 0 ]]; then
    echo "Error: Unable to create volume." | tee -a $log
    exit 1
fi
echo "$result" | tee -a $log
volume_id=$(echo "$result" | awk -F'"' '/"VolumeId":/{print $4}')
state=""
while [[ $state != "available" ]]; do
    result=$(aws --profile "$profile" $region_opt ec2 describe-volumes --volume-ids "$volume_id" --output json)
    state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
    echo -n "."
    sleep 1
done
echo "Done." | tee -a $log

echo "Attach volume..." | tee -a $log
aws --profile "$profile" $region_opt ec2 attach-volume --volume-id "$volume_id" --instance-id "$instance_id" --device "$device" | tee -a $log
attachment_state=""
while [[ $attachment_state != "attached" ]]; do
    result=$(aws --profile "$profile" $region_opt ec2 describe-volumes --volume-ids "$volume_id" --query 'Volumes[*].{State:Attachments[0].State}' --output json)
    attachment_state=$(echo "$result" | awk -F'"' '/"State":/{print $4}')
    echo -n "."
    sleep 1
done
echo "Done." | tee -a $log

if [[ $volume_mount ]]; then
    echo "Mount volume..." | tee -a $log
    ssh "$instance" "echo '$device $volume_mount auto defaults,auto,noatime,noexec 0 0' | sudo tee -a /etc/fstab > /dev/null; sudo mkdir $volume_mount; sudo mount -a" | tee -a $log
    rc=$?
    if [[ $rc -gt 0 ]]; then
        echo "Error: Could not mount volume." | tee -a $log
        exit 1
    fi
    echo "Done." | tee -a $log
fi
