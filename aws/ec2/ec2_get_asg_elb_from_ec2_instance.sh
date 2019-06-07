#!/usr/bin/env bash

# Purpose:
#     Get Autoscaling Group and Load Balancer information given an instance.
# Usage:
#     Run script with --help option to get usage.

version="1.2.1"

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
    echo "Error: Instance name/id is missing." >&2
    echo >&2
    usage
fi

if echo "$name" | grep -q '^i-'; then
    instance_id="$name"
else
    instance_id=$(aws --profile "$profile" $region_opt ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to query AWS." >&2
        exit 1
    fi
fi

auto_scaling_group_name="$(aws --profile "$profile" $region_opt ec2 describe-tags --filters "Name=resource-id,Values=$instance_id" "Name=key,Values=aws:autoscaling:groupName" | jq -r '.Tags[].Value')"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to query AWS." >&2
    exit 1
fi

auto_scaling_group="$(aws --profile "$profile" $region_opt autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$auto_scaling_group_name")"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to query AWS." >&2
    exit 1
fi

echo "$auto_scaling_group" | jq '.AutoScalingGroups[] | {AutoScalingGroupName, LaunchConfigurationName, MinSize, MaxSize, DesiredCapacity, LoadBalancerNames, HealthCheckType, Instances}'
echo

load_balancer_names="$(echo "$auto_scaling_group" | jq -r '.AutoScalingGroups[].LoadBalancerNames[]')"
load_balancers="$(aws --profile "$profile" $region_opt elb describe-load-balancers --load-balancer-names "$load_balancer_names" | jq '.LoadBalancerDescriptions')"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to query AWS." >&2
    exit 1
fi

echo "$load_balancers" | jq '.[] | {LoadBalancerName, DNSName, ListenerDescriptions, Instances, HealthCheck}'
