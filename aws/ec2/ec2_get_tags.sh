#!/bin/bash

# Purpose:
#     Get tags for AWS resource such as EC2 instance.
# Usage:
#     Run script with --help option to get usage.

version="1.1.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name resource"
    echo
    echo "Example:"
    echo "    $script_name i-abcd1234"
    echo "    or"
    echo "    $script_name vol-abcd1234"
    echo "    or"
    echo "    $script_name myinstancename"
    exit 1
}

get_instance_id() {
    local name
    local instance_id
    local rc

    name="$1"

    if echo "$name" | grep -q '^i-'; then
        instance_id="$name"
    else
        instance_id=$(aws --profile "$profile" $region_opt ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "Error: Failed to query AWS." 1>&2
            exit 1
        fi
    fi
    if [[ -z $instance_id ]]; then
        echo "Error: Instance was not found." 1>&2
        exit 1
    fi
    echo "$instance_id"
}

if [[ $1 == "--help" || -z $1 ]]; then
    usage
fi

resource="$1"
echo -n "$resource "

if echo "$resource" | grep -q '^vol-'; then
    # TODO: Need to return volume tags.
    echo "$resource" # DEBUG
else
    instance_id="$(get_instance_id "$resource")"
    aws --profile "$profile" $region_opt ec2 describe-instances --instance-ids "$instance_id" --output json --query 'Reservations[0].Instances[0].Tags' | jq -r '.[] | "Key=" + .Key + ",Value=" + .Value' | tr '\n' ' '
fi
echo
