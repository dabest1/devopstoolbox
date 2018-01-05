#!/bin/bash

# Purpose:
#     List autoscaling activities.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

asg_group="$1"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name asg_group"
    echo
    echo "Example:"
    echo "    $script_name my_asg_group_name"
    exit 1
}

if [[ $1 == "--help" || -z $1 ]]; then
    usage
fi

aws --profile "$profile" autoscaling describe-scaling-activities --auto-scaling-group-name "$asg_group"
