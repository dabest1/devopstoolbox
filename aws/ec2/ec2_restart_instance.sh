#!/usr/bin/env bash

# Purpose:
#     Restart EC2 instance.
# Usage:
#     Run script with --help option to get usage.
# Todo:
#     Add prompt for confirmation before restart.

version="1.1.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

function usage {
    cat <<USAGE
Usage:
    [export AWS_PROFILE=profile]
    $script_name [--profile profile] [--region region] name

Example:
    $script_name myhost

Description:
    --profile     Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE environment variable.
    --region      Use a specified region instead of region from configuration or environment setting.
    -h, --help    Display this help.
USAGE
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
        region_opt="--region $region"
        shift
        ;;
    *)
        name="$1"
        shift
    esac
done

# If name is not supplied, then show usage.
if [[ -z $name ]]; then
    usage
fi

if echo "$name" | grep -q '^i-'; then
    instance_ids="$name"
else
    instance_ids=$(aws --profile "$profile" $region_opt ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
fi
if [[ -z $instance_ids ]]; then
    exit 1
fi

aws --profile "$profile" $region_opt ec2 reboot-instances --instance-ids $instance_ids
