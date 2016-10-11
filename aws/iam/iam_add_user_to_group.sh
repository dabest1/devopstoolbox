#!/bin/bash

# Purpose:
#     Add IAM user to group.
# Usage:
#     Run script with --help option to get usage.

version="1.0.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

username="$1"
groupname="$2"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name username groupname"
    echo
    echo "Example:"
    echo "    $script_name john.doe admins"
    exit 1
}

if [[ $1 == "--help" || -z $1 || -z $2 ]]; then
    usage
fi

aws --profile "$profile" iam add-user-to-group --user-name "$username" --group-name "$groupname"
