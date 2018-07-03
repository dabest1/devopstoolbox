#!/bin/bash

# Purpose:
#     Provides a list of one or more instances with their status.
#     Multiple instances can be displayed if partial name with wildcard is 
#     supplied.
# Usage:
#     Run script with --help option to get usage.

version="1.5.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [--profile profile] [--region region] [name | 'partial_name*' | -v tag-value]"
    echo
    echo "Description:"
    echo "    --profile          Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE variable."
    echo "    --region           Use a specified region instead of region from configuration or environment setting."
    echo "    -v, --tag-value    List instances which have the provided tag value in any of the tag keys."
    echo "    -h, --help         Display this help."
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
    -v|--tag-value)
        shift
        tag_value="$1"
        shift
        ;;
    *)
        name="$1"
        shift
    esac
done

# Header row.
header_row="Profile Name InstanceId PrivateIp PublicIp KeyName AZ Type State"

{
    echo "$header_row"

    # If tag is not supplied, then search by name, else search by tag.
    if [[ -z $tag_value ]]; then
        # If name is not supplied, then we want all instances.
        if [[ -z $name ]]; then
            name='*'
        fi

        if echo "$name" | grep -q '^i-'; then
            instance_ids="$name"
        else
            instance_ids=$(aws --profile "$profile" $region_opt ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
        fi
        if [[ -z $instance_ids ]]; then
            exit 1
        fi

        aws --profile "$profile" $region_opt ec2 describe-instances --instance-ids $instance_ids --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, PrivateIpAddress, PublicIpAddress, KeyName, Placement.AvailabilityZone, InstanceType, State.Name]' --output text | sort | awk -v profile="$profile" '{print profile"\t"$0}'
    else
        aws --profile "$profile" $region_opt ec2 describe-instances --filter "Name=tag-value,Values=$tag_value" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value | [0], InstanceId, PrivateIpAddress, PublicIpAddress, KeyName, Placement.AvailabilityZone, InstanceType, State.Name]' --output text | sort | awk -v profile="$profile" '{print profile"\t"$0}'
    fi
} | column -t
