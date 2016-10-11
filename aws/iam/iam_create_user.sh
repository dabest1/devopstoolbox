#!/bin/bash

# Purpose:
#     Create IAM user.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

username="$1"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name username"
    echo
    echo "Example:"
    echo "    $script_name john.doe"
    exit 1
}

if [[ $1 == "--help" || -z $1 ]]; then
    usage
fi

aws --profile "$profile" iam create-user --user-name "$username"
