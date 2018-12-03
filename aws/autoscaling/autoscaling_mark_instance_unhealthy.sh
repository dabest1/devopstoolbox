#!/bin/bash

# Purpose:
#     Set autoscaling instance health to unhealthy.
# Usage:
#     Run script with --help option to get usage.

version="1.2.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [--profile profile] [--region region] {name | instance_id} ..."
    echo
    echo "Example:"
    echo "    $script_name i-abcd1234"
    echo
    echo "Description:"
    echo "    --profile     Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE variable."
    echo "    --region      Use a specified region instead of region from configuration or environment setting."
    echo "    -h, --help    Display this help."
    exit 1
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
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
    *)
        if [[ -z $names ]]; then
            names="$1"
        else
            names="$names $1"
        fi
        shift
    esac
done

if [[ -z $names ]]; then
    usage
fi

for name in $names; do
    if echo "$name" | grep -q '^i-'; then
        instance_id="$name"
    else
        echo "name: $name"
        instance_id=$(aws --profile "$profile" $region_opt ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to query AWS."
            exit 1
        fi
    fi
    echo "instance_id: $instance_id"

    aws --profile "$profile" $region_opt autoscaling set-instance-health --instance-id "$instance_id" --health-status "Unhealthy"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to set health status."
        exit 1
    fi
    echo
done
