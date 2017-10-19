#!/bin/bash

# Purpose:
#     Provides information about a volume.
#     Multiple volumes can be displayed if wildcard is used.
# Usage:
#     Run script with --help option to get usage.

version="1.1.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [instance_name | 'partial_name*' | instance_id]"
    exit 1
}

name="$1"
profile="${AWS_PROFILE:-default}"

if [[ $1 == "--help" || $1 == "-h" ]]; then
    usage
fi

# If name is not supplied, then we want all instances.
if [[ -z $name ]]; then
    name='*'
fi

echo "profile: $profile"
echo

{
    echo "DeleteOnTermination Device InstanceId Size State VolumeId"

    if echo "$name" | grep -q '^i-'; then
        instance_id="$name"
        aws --profile "$profile" ec2 describe-volumes --filters "Name=attachment.instance-id, Values=$instance_id" --query 'Volumes[*].{VolumeId:VolumeId,InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,DeleteOnTermination:Attachments[0].DeleteOnTermination,Device:Attachments[0].Device,Size:Size}' --output text
    elif [[ $name == '*' ]]; then
        aws --profile "$profile" ec2 describe-volumes --query 'Volumes[*].{VolumeId:VolumeId,InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,DeleteOnTermination:Attachments[0].DeleteOnTermination,Device:Attachments[0].Device,Size:Size}' --output text
    else
        instance_ids=$(aws --profile "$profile" ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
        if [[ -z $instance_ids ]]; then
            exit 1
        fi
        for instance_id in $instance_ids; do
            aws --profile "$profile" ec2 describe-volumes --filters "Name=attachment.instance-id, Values=$instance_id" --query 'Volumes[*].{VolumeId:VolumeId,InstanceId:Attachments[0].InstanceId,State:Attachments[0].State,DeleteOnTermination:Attachments[0].DeleteOnTermination,Device:Attachments[0].Device,Size:Size}' --output text
        done
    fi
} | column -t
