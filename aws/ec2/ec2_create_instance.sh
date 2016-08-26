#!/bin/bash

# Purpose:
#     Create EC2 instance.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

image_id="$1"
instance_type="$2"
subnet_id="$3"
key_name="$4"
security_group_ids="$5"
iam_instance_profile="$6"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name image_id instance_type subnet_id key_name security_group_ids iam_instance_profile"
    echo
    echo "Example:"
    echo "    $script_name ami-1234abcd r3.large subnet-1234abcd mykey sg-1234abcd Name=my_iam_profile"
    exit 1
}

if [[ $1 == "--help" || -z $1 || -z $2 || -z $3 || -z $4 || -z $5 || -z $6 ]]; then
    usage
fi

result="$(aws ec2 run-instances --image-id "$image_id" --instance-type "$instance_type" --subnet-id "$subnet_id" --key-name "$key_name" --security-group-ids "$security_group_ids" --iam-instance-profile "$iam_instance_profile")"
echo "$result"
echo
instance_id=$(echo "$result" | grep 'InstanceId' | awk -F'"' '{print $4}')
echo "instance_id: $instance_id"
