#!/bin/bash

# Purpose:
#     Terminate AWS instance and delete attached volumes.
# Usage:
#     Run script with --help option to get usage.

version="1.0.5"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"
failures=0

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [-f] {name | instance_id}"
    echo
    echo "Description:"
    echo "    -f, --force   Do not prompt for confirmation."
    echo "    -h, --help    Show this help."
    exit 1
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
        ;;
    -f|--force)
        do_not_prompt="yes"
        shift
        ;;
    *)
        name="$1"
        shift
    esac
done
profile="${AWS_PROFILE:-default}"

if [[ -z $name ]]; then
    usage
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
if echo "$name" | grep -q '^i-'; then
    instance_id="$name"
else
    echo "name: $name" | tee -a $log
    instance_id=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
fi
echo "instance_id: $instance_id" | tee -a $log
if [[ -z $instance_id ]]; then
    exit 1
fi

aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, Placement.AvailabilityZone, InstanceType, State.Name]' --output table
aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --output table >> $log

aws --profile "$profile" ec2 describe-volumes --filters "Name=attachment.instance-id, Values=$instance_id" --query 'Volumes[*].{VolumeId:VolumeId,InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,DeleteOnTermination:Attachments[0].DeleteOnTermination,Device:Attachments[0].Device,Size:Size}' --output table | tee -a $log

volume_ids=$(aws --profile "$profile" ec2 describe-volumes --filters "Name=attachment.instance-id, Values=$instance_id" "Name=attachment.delete-on-termination, Values=false" --query 'Volumes[*].[VolumeId]' --output text)

if [[ $do_not_prompt != "yes" ]]; then
    echo -n "Are you sure that you want this instance terminated? y/n: "
    read yn
    if [[ $yn != y ]]; then
        echo "Aborted!" | tee -a $log
        exit 1
    fi
    echo
fi

aws --profile "$profile" ec2 terminate-instances --instance-ids "$instance_id" --output table | tee -a $log

if [[ -z $volume_ids ]]; then
    exit 0
fi
echo "volume_ids:" $volume_ids | tee -a $log

if [[ $do_not_prompt != "yes" ]]; then
    echo -n "Are you sure that you want these volumes deleted? y/n: "
    read yn
    if [[ $yn != y ]]; then
        echo "Aborted!" | tee -a $log
        exit 1
    fi
    echo
fi

for volume_id in $volume_ids; do
    echo "Deleting volume_id: $volume_id" | tee -a $log
    aws --profile "$profile" ec2 delete-volume --volume-id "$volume_id" &> /dev/null
    return_code=$?
    while [[ $return_code -eq 255 ]]; do # Wait until the instance is terminated to delete the volume.
        echo -n "."
        sleep 10
        aws --profile "$profile" ec2 delete-volume --volume-id "$volume_id" &> /dev/null
        return_code=$?
    done
    if [[ $return_code -ne 0 ]]; then
        echo "Error: Could not delete volume." | tee -a $log
        echo "return_code: $return_code" | tee -a $log
        failures+=1
    else
        echo "done" | tee -a $log
    fi
done

exit "$failures"
