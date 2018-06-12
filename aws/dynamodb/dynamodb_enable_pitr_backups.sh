#!/bin/bash
################################################################################
# Purpose:
#     Enables PITR Backup of DynamoDB tables.
# Usage:
#     Run script with --help option to get usage.
################################################################################

version="1.0.0"

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

# Functions.

# Usage.
usage() {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name table_name"
    echo
    echo "Description:"
    echo "    Enables PITR Backup for requested DynamoDB tables."
    echo "    If AWS_PROFILE is not exported, then 'default' profile will be used."
    echo "    "
    echo "    Options:"
    echo "    table_name    Supply table_name or a regex to filter for which tables PITR backup will be enabled. Regex is the same as used by grep."
    echo "    --version     Display script version."
    echo "    --help        Display this help."
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
    *)
        table_name=$1
        shift
        ;;
    --help)
        usage
    esac
done

echo "profile: $profile"
echo
echo "Tables for which PITR Backup will be enabled:"
tables="$(aws --profile "$profile" dynamodb list-tables --output text | awk '{print $2}' | grep "$table_name")"
echo "$tables"
echo

echo -n 'Are you sure that you want to proceed? y/n: '
read -r yn
if [[ $yn != y ]]; then
    echo 'Aborted!'
    exit 1
fi
echo

for table in $tables; do
    echo "Enabling PITR Backup for table: $table"
    aws --profile "$profile" dynamodb update-continuous-backups --table-name "$table" --point-in-time-recovery-specification PointInTimeRecoveryEnabled=True
done
echo

echo "Done."
