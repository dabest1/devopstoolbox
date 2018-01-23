#!/bin/bash

# Purpose:
#     Restore AWS DynamoDB tables. Script wrapper for dynamodump.py.
# Usage:
#     Run script with --help option to get usage.

version="1.0.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

# Load configuration settings.
source "$config_path"

bkup_dir=$1

if [[ $1 == '--help' || -z $1 ]]; then
    echo 'Usage:'
    echo "    $script_name backup_dir"
    echo 'Example:'
    echo "    $script_name 20160623T225858Z"
    exit 1
fi

start_time="$(date -u +'%F %T %Z')"
ts="$(date -d "$start_time" +'%Y%m%dT%H%M%SZ')"

echo "**************************************************"
echo "* Restore AWS DynamoDB Tables"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "Hostname: $HOSTNAME"
echo
echo "Size of backup to restore:"
du -s "$bkup_dir/"*
echo

echo "Creating dump symlink."
ln -s "$bkup_dir" dump
echo

for table in $tables; do
    date -u +'TS: %Y%m%dT%H%M%SZ'
    echo "Table: $table"
    $dynamodump -r $region --accessKey $accessKey --secretKey $secretKey -m restore --writeCapacity "$writeCapacity" -s $table -d $table
    #$dynamodump -r $region --accessKey $accessKey --secretKey $secretKey -m restore --writeCapacity "$writeCapacity" -s $table -d new_table_name
    echo
done

date -u +'TS: %Y%m%dT%H%M%SZ'
echo "Removing dump symlink."
rm dump

echo
echo "**************************************************"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"
