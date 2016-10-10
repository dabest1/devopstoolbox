#!/bin/bash

# Purpose:
#     Change autoscale capacity.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

name="$1"
desired="$2"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name asg_name desired_capacity"
    echo
    echo "Example:"
    echo "    $script_name my_auto_scaling_group 5"
    exit 1
}

if [[ $1 == "--help" || -z $name || -z $desired ]]; then
    usage
fi

# Output to screen and log to file.
exec 1> >(tee -ia "$log") 2> >(tee -ia "$log" >&2)

echo >> "$log"
date +'%F %T %z' >> "$log"
echo "profile: $profile"

aws --profile "$profile" autoscaling set-desired-capacity --auto-scaling-group-name "$name" --desired-capacity "$desired"
