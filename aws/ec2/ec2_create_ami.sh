#!/bin/bash

# Purpose:
#     Creates Amazon EBS-backed AMI (Amazon Machine Image).
# Usage:
#     Run script with --help option to get usage.
# Todo:
#     Add tagging of AMI and/or snapshot based on source.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

usage() {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [--profile profile] [--region region] {name | instance_id} image_name [description]"
    echo
    echo "Description:"
    echo "    --profile          Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE variable."
    echo "    --region           Use a specified region instead of region from configuration or environment setting."
    echo "    -h, --help         Display this help."
    exit 1
}

get_instance_id() {
    local name
    local instance_id

    name=$1

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
        name="$1"
        shift
        image_name="$1"
        shift
        description="$1"
        shift
    esac
done

if [[ -z $name || -z $image_name ]]; then
    usage
fi

echo "name: $name"
echo "image_name: $image_name"
echo "description: $description"
echo

instance_id="$(get_instance_id "$name")"

aws --profile "$profile" $region_opt ec2 create-image --instance-id "$instance_id" --name "$image_name" --description "$description"
