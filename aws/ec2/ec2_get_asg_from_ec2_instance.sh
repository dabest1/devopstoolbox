#!/usr/bin/env bash

# Purpose:
#     Get Autoscaling Group and Load Balancer information given an instance.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

function usage {
    cat <<USAGE
Usage:
    [export AWS_PROFILE=profile]
    $script_name [--profile profile] [--region region] {name | instance_id}

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

if [[ -z $name ]]; then
    echo "Error: Instance name/id is missing."
    echo
    usage
fi

if echo "$name" | grep -q '^i-'; then
    instance_id="$name"
    auto_scaling_group="$(aws --profile "$profile" $region_opt ec2 describe-tags --filters "Name=resource-id,Values=$instance_id" | jq -r '.Tags[] | select(.Key=="aws:autoscaling:groupName") | .Value')"
else
    auto_scaling_group="$(aws --profile "$profile" $region_opt ec2 describe-tags --filters "Name=tag:Name,Values=$name" | jq -r '.Tags[] | select(.Key=="aws:autoscaling:groupName") | .Value')"
fi

echo "Auto Scaling Group: $auto_scaling_group"
