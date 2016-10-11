#!/bin/bash

# Purpose:
#     Create IAM group.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

groupname="$1"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name group"
    echo
    echo "Example:"
    echo "    $script_name admins"
    exit 1
}

if [[ $1 == "--help" || -z $1 ]]; then
    usage
fi

aws --profile "$profile" iam create-group --group-name "$groupname"
