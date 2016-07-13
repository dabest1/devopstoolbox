#!/bin/bash

# Purpose:
#     Stop AWS instance.
# Usage:
#     Run script with no options to get usage.

version='1.0.0'

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

name="$1"
profile="${AWS_PROFILE:-default}"

if [[ -z $name ]]; then
    echo 'Usage:'
    echo '    export AWS_PROFILE=profile'
    echo "    $script_name name|instance_id"
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
if echo "$name" | grep -q 'i-'; then
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

echo -n 'Are you sure that you want this instance stopped? y/n: '
read yn
if [[ $yn == y ]]; then
    aws --profile "$profile" ec2 stop-instances --instance-ids "$instance_id" --output table | tee -a $log
else
    echo 'Aborted!' | tee -a $log
    exit 1
fi
