#!/bin/bash

# Purpose:
#     Provides a list of one or more instances with their status.
#     Multiple instances can be displayed if partial name with wildcard is 
#     supplied.
# Usage:
#     Run script with -h option to get usage.

version=1.0.5

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

name="$1"
profile="${AWS_PROFILE:-default}"

if [[ $1 == '-h' ]]; then
    echo 'Usage:'
    echo '    export AWS_PROFILE=profile'
    echo "    $script_name [name]"
    echo '    or'
    echo "    $script_name 'partial_name*'"
    exit 1
fi

# If name is not supplied, then we want all instances.
if [[ -z $name ]]; then
    name='*'
fi

echo "profile: $profile"
if echo "$name" | grep -q 'i-'; then
    instance_ids="$name"
else
    #echo "name: $name"
    instance_ids=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
fi
#echo "instance_ids:" $instance_ids
if [[ -z $instance_ids ]]; then
    exit 1
fi

echo
aws --profile "$profile" ec2 describe-instances --instance-ids $instance_ids --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, Placement.AvailabilityZone, InstanceType, State.Name]' --output text | sort