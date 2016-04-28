#!/bin/bash

# Purpose:
#     Provides a list of one or more instances with their status.
#     Multiple instances can be displayed if partial name with wildcard is 
#     supplied.
# Usage:
#     Run script with -h option to get usage.

version=1.0.2

name="$1"
profile="$AWS_PROFILE"

if [[ -z $profile || $1 == '-h' ]]; then
    echo 'Usage:'
    echo '    export AWS_PROFILE=profile'
    echo '    script.sh [name]'
    echo '    or'
    echo "    script.sh 'partial_name*'"
    exit 1
fi
if [[ -z $1 ]]; then
    name='*'
fi

echo "profile: $profile"
echo "name: $name"
instance_ids=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
return_code=$?
if [[ $return_code -ne 0 ]]; then
    exit 1
fi
echo "instance_ids:" $instance_ids
if [[ -z $instance_ids ]]; then
    exit 1
fi
aws --profile "$profile" ec2 describe-instances --instance-ids $instance_ids --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, Placement.AvailabilityZone, InstanceType, State.Name]' --output table
