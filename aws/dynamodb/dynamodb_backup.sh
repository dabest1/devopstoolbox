#!/bin/bash

# Purpose:
#     Backup AWS DynamoDB tables. Wrapper script for dynamodump.py (https://github.com/bchew/dynamodump).
# Usage:
#     Run script with --help option to get usage.

version="1.1.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

usage() {
    echo "Usage:"
    echo "    Set options in $config_path config file."
    echo "    $script_name"
    exit 1
}

# Load configuration settings.
source "$config_path"

if [[ $1 == '--help' ]]; then
    usage
fi

start_time="$(date -u +'%F %T %Z')"
bkup_ts="$(date -d "$start_time" +'%Y%m%dT%H%M%SZ')"

echo "**************************************************"
echo "* Backup AWS DynamoDB Tables"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "Hostname: $HOSTNAME"
echo "bkup_ts: $bkup_ts"
echo "script: $script_dir/$script_name"
echo "dynamodump: $dynamodump"
echo "readCapacity: $readCapacity"
echo "region: $region"
echo "tables_include: $tables_include"
echo "tables_exclude: $tables_exclude"
echo

echo "All tables in the region:"
tables_all="$(aws --profile "$aws_profile" dynamodb list-tables --output text | awk '{print $2}')"
echo "$tables_all"
echo

echo "Tables selected for backup:"
tables_backup="$(echo "$tables_all" | egrep "$tables_include" | egrep -v "$tables_exclude")"
echo "$tables_backup"
echo

for table in $tables_backup; do
    date -u +'TS: %Y%m%dT%H%M%SZ'
    echo "Table: $table"
    $dynamodump -r "$region" --accessKey "$accessKey" --secretKey "$secretKey" -m backup --readCapacity "$readCapacity" -s "$table"
    echo
done

date -u +'TS: %Y%m%dT%H%M%SZ'
mv -v dump "$bkup_ts"
echo "Size of backup (KB):"
du -s "$bkup_ts/"*
echo

echo "**************************************************"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"
