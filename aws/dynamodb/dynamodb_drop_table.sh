#!/bin/bash

# Purpose:
#     Drop DynamoDB table.
# Usage:
#     Run script with no options to get usage.

version='1.0.0'

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

table="$1"
profile="${AWS_PROFILE:-default}"

if [[ -z $table ]]; then
    echo 'Usage:'
    echo '    export AWS_PROFILE=profile'
    echo "    $script_name table"
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
if [[ -z $table ]]; then
    exit 1
fi
echo "table: $table" | tee -a $log

echo -n 'Are you sure that you want this table dropped? y/n: '
read yn
if [[ $yn == y ]]; then
    aws --profile "$profile" dynamodb delete-table --table-name "$table" | tee -a $log
else
    echo 'Aborted!' | tee -a $log
    exit 1
fi
