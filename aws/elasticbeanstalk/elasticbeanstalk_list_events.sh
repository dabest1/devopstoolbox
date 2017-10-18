#!/bin/bash

# Purpose:
#     Provides a list of ElastiCache events.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name environment_name"
    echo
    echo "Description:"
    echo "    -h, --help         Display this help."
    exit 1
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
        ;;
    *)
        environment_name="$1"
        shift
    esac
done

if [[ -z $environment_name ]]; then
    aws --profile "$profile" elasticbeanstalk describe-events --output text
else
    aws --profile "$profile" elasticbeanstalk describe-events --environment-name "$environment_name" --output text
fi
