#!/bin/bash

# Purpose:
#     Set autoscaling instance health to unhealthy.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

instance_id="$1"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name instance_id"
    echo
    echo "Example:"
    echo "    $script_name i-abcd1234"
    exit 1
}

if [[ $1 == "--help" || -z $1 ]]; then
    usage
fi

aws --profile "$profile" autoscaling set-instance-health --instance-id "$instance_id" --health-status "Unhealthy"
