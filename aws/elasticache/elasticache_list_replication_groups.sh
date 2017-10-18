#!/bin/bash

# Purpose:
#     Provides a list of ElastiCache replication groups.
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
    echo "    $script_name [replication_group_id]"
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
        replication_group_id="$1"
        shift
    esac
done

if [[ -z $replication_group_id ]]; then
    aws --profile "$profile" elasticache describe-replication-groups --output text
else
    aws --profile "$profile" elasticache describe-replication-groups --replication-group-id "$replication_group_id" --output text
fi
