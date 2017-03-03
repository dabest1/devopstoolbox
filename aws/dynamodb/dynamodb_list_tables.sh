#!/bin/bash
################################################################################
# Purpose:
#     Provides a list of DynamoDB tables. AWS paginates the output at 100 items 
#     per page.
# Usage:
#     Run script with --help option to get usage.
################################################################################

version="1.1.0"

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

# Functions.

# Usage.
usage() {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name"
    echo
    echo "Description:"
    echo "    Running the script with no options will display a list of DynamoDB tables."
    echo "    Output is paginated at 100 items per page."
    echo "    If AWS_PROFILE is not exported, then 'default' profile will be used."
    echo "    "
    echo "    Options:"
    echo "    --version                  Display script version."
    echo "    --help                     Display this help."
    exit 1
}

set -o pipefail

profile="${AWS_PROFILE:-default}"

# Process options.
while [[ -n $1 ]]; do
    case "$1" in
    --version)
        echo "version: $version"
        exit
        ;;
    *|--help)
        usage
    esac
done

echo "profile: $profile"
echo
aws --profile "$profile" dynamodb list-tables --output text | awk '{print $2}'
