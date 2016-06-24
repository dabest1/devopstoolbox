#!/bin/bash

# Purpose:
#     Backup AWS DynamoDB tables. Script wrapper for dynamodump.py.
# Usage:
#     Run script with --help option to get usage.

version="1.0.3"

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
echo "tables: $tables"
echo

for table in $tables; do
    date -u +'TS: %Y%m%dT%H%M%SZ'
    echo "Table: $table"
    $dynamodump -r "$region" --accessKey "$accessKey" --secretKey "$secretKey" -m backup --readCapacity "$readCapacity" -s "$table"
    echo
done

date -u +'TS: %Y%m%dT%H%M%SZ'
mv -v dump "$bkup_ts"
echo "Size of backup:"
du -s "$bkup_ts/"*
echo

echo "**************************************************"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"
