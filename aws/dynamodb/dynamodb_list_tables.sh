#!/bin/bash

# Purpose:
#     Provides a list of DynamoDB tables. AWS paginates the output at 100 items per page.
# Usage:
#     Run script with -h option to get usage.

version=1.0.0

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

if [[ $1 == '-h' ]]; then
    echo 'Usage:'
    echo '    export AWS_PROFILE=profile'
    echo "    $script_name"
    exit 1
fi

echo "profile: $profile"
echo
aws --profile "$profile" dynamodb list-tables --output text | awk '{print $2}'
