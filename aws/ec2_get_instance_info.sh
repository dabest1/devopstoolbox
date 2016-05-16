#!/bin/bash

# Purpose:
#     Prints essential information about the instance name supplied.
#     Information about multiple instances can be displayed if partial name 
#     with wildcard is supplied.
# Usage:
#     Run script with -h option to get usage.

version=1.0.4

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

name="$1"
profile="${AWS_PROFILE:-default}"

if [[ -z $name || $1 == '-h' ]]; then
    echo 'Usage:'
    echo '    export AWS_PROFILE=profile'
    echo "    $script_name name"
    echo '    or'
    echo "    $script_name 'partial_name*'"
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo "name: $name" | tee -a $log
instance_ids=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
echo "instance_ids:" $instance_ids | tee -a $log
if [[ -z $instance_ids ]]; then
    exit 1
fi

for instance_id in $instance_ids; do
    echo | tee -a $log
    aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, Placement.AvailabilityZone, InstanceType, State.Name]' --output table | tee -a $log
    aws --profile "$profile" ec2 describe-volumes --filters "Name=attachment.instance-id, Values=$instance_id" --query 'Volumes[*].{VolumeId:VolumeId,InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,DeleteOnTermination:Attachments[0].DeleteOnTermination,Device:Attachments[0].Device,Size:Size}' --output table | tee -a $log
done
