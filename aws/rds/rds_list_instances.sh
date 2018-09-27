#!/bin/bash

# Purpose:
#     Provides a list of one or multiple RDS instances with their status.
# Usage:
#     Run script with --help option to get usage.

version="2.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [--profile profile] [--region region] [name]"
    exit 1
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
        ;;
    --profile)
        shift
        profile="$1"
        shift
        ;;
    --region)
        shift
        region="$1"
        region_opt="--region=$region"
        shift
        ;;
    *)
        name="$1"
        shift
    esac
done

# Header row.
header_row="account name engine region class status endpoint port"

{
    echo "$header_row"
    aws --profile "$profile" rds describe-db-instances --db-instance-identifier "$name" | jq '.DBInstances[] | [.DBInstanceIdentifier, .Engine, .AvailabilityZone, .DBInstanceClass, .DBInstanceStatus, .Endpoint.Address, .Endpoint.Port] | @tsv' | tr -d '"' | sed 's/\\t/ /g' | awk -v profile="$profile" '{print profile" "$0}'
} | column -t
