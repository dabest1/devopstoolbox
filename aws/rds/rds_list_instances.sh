#!/bin/bash

# Purpose:
#     Provides a list of one or multiple RDS instances with their status.
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

# Header row.
header_row="account	name	engine	region	class	status"

echo "$header_row"
aws --profile "$profile" rds describe-db-instances --db-instance-identifier "$name" | jq '.DBInstances[] | [.DBInstanceIdentifier, .Engine, .AvailabilityZone, .DBInstanceClass, .DBInstanceStatus] | @tsv' | tr -d '"' | sed 's/\\t/	/g' | awk -v profile="$profile" '{print profile"\t"$0}'
