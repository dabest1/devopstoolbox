#!/bin/bash

# Purpose:
#     Backup AWS DynamoDB tables. Script wrapper for dynamodump.py.
# Usage:
#     Run script with --help option to get usage.

version="1.0.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

# Load configuration settings.
source "$config_path"

if [[ $1 == '--help' ]]; then
    echo 'Usage:'
    echo "    $script_name"
    exit 1
fi

for table in $tables; do
    echo "Table: $table"
    $dynamodump -r $region --accessKey $accessKey --secretKey $secretKey -m backup -s $table
    #$dynamodump -r $region --accessKey $accessKey --secretKey $secretKey -m restore -s $table -d new_table_name 
done
