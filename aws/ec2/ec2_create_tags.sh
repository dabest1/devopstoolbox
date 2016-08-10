#!/bin/bash

# Purpose:
#     Create tags for AWS resource such as EC2 instance.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

resources="$1"
tags="$2"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name resources tags"
    echo
    echo "Example:"
    echo "    $script_name i-abcd1234 \"Key=string,Value=string\""
    echo "    or"
    echo "    $script_name \"i-abcd1234 vol-abcd1234\" \"Key=string,Value=string Key=string,Value=string\""
    exit 1
}

if [[ $1 == "--help" || -z $1 || -z $2 ]]; then
    usage
fi

aws ec2 create-tags --resources "$resources" --tags $tags
