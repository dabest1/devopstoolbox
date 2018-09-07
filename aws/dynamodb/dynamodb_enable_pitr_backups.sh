#!/bin/bash
################################################################################
# Purpose:
#     Enables PITR Backup of DynamoDB tables.
# Usage:
#     Run script with --help option to get usage.
################################################################################

version="2.0.0"

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

# Functions.

shopt -s expand_aliases
alias die='error_exit "ERROR in $0: line $LINENO:"'

# Usage.
usage() {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [--profile profile] --tables-include 'regex' [--tables-exclude 'regex'] [--no-prompt]"
    echo
    echo "Description:"
    echo "    Enables PITR Backup for requested DynamoDB tables."
    echo "    "
    echo "    Options:"
    echo "    -e, --tables-exclude    List of DynamoDB tables to be excluded. Supports grep regular expression."
    echo "    -i, --tables-include    List of DynamoDB tables to be included. Supports grep regular expression."
    echo "    -n, --no-prompt         No confirmation prompt."
    echo "    --profile               Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE variable."
    echo "    --region                Use a specified region instead of region from configuration or environment setting."
    echo "    --version               Display script version."
    echo "    --help                  Display this help."
    exit 1
}

error_exit() {
    echo "$@" >&2
    exit 77
}

profile="${AWS_PROFILE:-default}"

set -E
set -o pipefail
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

# Process options.
while [[ -n $1 ]]; do
    case "$1" in
    -n|--no-prompt)
        do_not_prompt="yes"
        shift
        ;;
    -i|--tables-include)
        shift
        tables_include="$1"
        shift
        ;;
    -e|--tables-exclude)
        shift
        tables_exclude="$1"
        shift
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
    --version)
        echo "version: $version"
        exit
        ;;
    *)
        usage
    esac
done

if [[ -z $tables_include ]]; then
    usage
fi

echo "profile: $profile"
echo
echo "Tables for which PITR Backup will be enabled:"
tables="$(aws --profile "$profile" $region_opt dynamodb list-tables --output text | awk '{print $2}')"
rc=$?
if [[ $rc -ne 0 ]]; then
    die "AWS command failed."
fi
tables="$(echo "$tables" | egrep "$tables_include")"
if [[ ! -z $tables_exclude ]]; then
    tables="$(echo "$tables" | egrep -v "$tables_exclude")"
fi
echo "$tables"
echo

if [[ ! $do_not_prompt ]]; then
    echo -n 'Are you sure that you want to proceed? y/n: '
    read -r yn
    if [[ $yn != y ]]; then
        echo 'Aborted!'
        exit 1
    fi
    echo
fi

for table in $tables; do
    echo "Enabling PITR Backup for table: $table"
    aws --profile "$profile" $region_opt dynamodb update-continuous-backups --table-name "$table" --point-in-time-recovery-specification PointInTimeRecoveryEnabled=True
    rc=$?
    if [[ $rc -ne 0 ]]; then
        die "AWS command failed."
    fi
done
echo

echo "Done."
