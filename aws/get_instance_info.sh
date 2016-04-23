#!/bin/bash

host="$1"
log='get_instance_info.log'
profile="$AWS_PROFILE"

if [[ -z $host || -z $profile ]]; then
    echo 'Usage:'
    echo '    AWS_PROFILE=profile'
    echo '    script.sh hostname'
    exit 1
fi

echo "profile: $profile"
echo "host: $host"

instance_id=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$host" --query 'Reservations[].Instances[].[InstanceId]' --output text)
return_code=$?
if [[ $return_code -ne 0 ]]; then
    exit 1
fi
echo "instance_id: $instance_id"

aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, Placement.AvailabilityZone, InstanceType, State.Name]' --output table | tee -a $log

aws --profile "$profile" ec2 describe-volumes --filters "Name=attachment.instance-id, Values=$instance_id" --query 'Volumes[*].{VolumeId:VolumeId,InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,DeleteOnTermination:Attachments[0].DeleteOnTermination,Device:Attachments[0].Device,Size:Size}' --output table | tee -a $log

aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" >> $log
