#!/bin/bash

# Purpose:
#     Get RDS instance information.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

name="$1"
profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [name]"
    exit 1
}

if [[ $1 == "--help" ]]; then
    usage
fi

aws --profile "$profile" rds describe-db-instances --db-instance-identifier "$name"
