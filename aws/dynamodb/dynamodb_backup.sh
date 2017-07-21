#!/bin/bash

# Purpose:
#     Backup AWS DynamoDB tables. Wrapper script for dynamodump.py (https://github.com/bchew/dynamodump).
# Usage:
#     Run script with --help option to get usage.

version="1.5.0"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"
log="$script_dir/${script_name/.sh/.log}"
log_err="$script_dir/${script_name/.sh/.err}"

# Functions.

shopt -s expand_aliases
alias die='error_exit "ERROR in $0: line $LINENO:"'

# Usage.
usage() {
    echo "Usage:"
    echo "    Set options in $config_path config file."
    echo "    $script_name"
    echo "Note:"
    echo "    dynamodump stalls when current read capacity matches the temporary backup read capacity. So try to set a unique value for read capacity during backup."
    exit 1
}

# Compress backup.
compress_backup() {
    echo "Compress backup."
    date -u +'start: %FT%TZ'
    find ./ -type f -exec gzip '{}' \;
    date -u +'finish: %FT%TZ'
    echo
    echo "Compressed backup size in bytes:"
    du -sb *
    echo "Disk space after compression:"
    df -h "$bkup_dir"
    echo
}

error_exit() {
    echo "$@" >&2
    exit 77
}

set -E
set -o pipefail
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

# Process options.
if [[ $1 == '--help' ]]; then
    usage
fi

# Load configuration settings.
source "$config_path"

if [[ -z $bkup_dir ]]; then
    die "Some variables were not provided in configuration file."
fi

# Redirect stderr into error log, stdout and stderr into log and terminal.
rm "$log" "$log_err" 2> /dev/null
exec 1> >(tee -ia "$log") 2> >(tee -ia "$log" >&2) 2> >(tee -ia "$log_err" >&2)

bkup_date="$(date -d "$start_time" +'%Y%m%dT%H%M%SZ')"

echo "**************************************************"
echo "* Backup AWS DynamoDB Tables"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "Hostname: $HOSTNAME"
echo "bkup_date: $bkup_date"
echo "script: $script_dir/$script_name"
echo "dynamodump: $dynamodump"
echo "readCapacity: $readCapacity"
echo "region: $region"
echo "tables_include: $tables_include"
echo "tables_exclude: $tables_exclude"
echo

bkup_type="daily"

echo "Backup will be created in: $bkup_dir/$bkup_date.$bkup_type"
echo
mkdir "$bkup_dir/$bkup_date.$bkup_type" || die "Cannot create directory."
# Move logs into dated backup directory.
mv "$log" "$bkup_dir/$bkup_date.$bkup_type/"
mv "$log_err" "$bkup_dir/$bkup_date.$bkup_type/"
log="$bkup_dir/$bkup_date.$bkup_type/$(basename "$log")"
log_err="$bkup_dir/$bkup_date.$bkup_type/$(basename "$log_err")"
cd "$bkup_dir/$bkup_date.$bkup_type" || die "Cannot change directory."

echo "All tables in the region:"
tables_all="$(aws --profile "$aws_profile" dynamodb list-tables --output text | awk '{print $2}')"
echo "$tables_all"
echo

echo "Tables selected for backup:"
tables_backup="$(echo "$tables_all" | egrep "$tables_include" | egrep -v "$tables_exclude")"
echo "$tables_backup"
echo

# Perform backup.
echo "Disk space before backup:"
df -h "$bkup_dir"
echo

for table in $tables_backup; do
    date -u +'start: %FT%TZ'
    echo "Table: $table"
    $dynamodump --region "$region" --profile "$aws_profile" --mode backup --readCapacity "$readCapacity" --srcTable "$table" 2>&1
    rc=$?
    if [[ $rc -ne 0 ]]; then
        die "dynamodump failed."
    fi
    echo
done
date -u +'backup finish: %FT%TZ'
echo

cd dump || die "Cannot change directory."

echo "Backup size in bytes:"
du -sb *
echo "Disk space after backup:"
df -h "$bkup_dir"
echo

compress_backup

echo "**************************************************"
echo "* Time finished: $(date -u +'%FT%TZ')"
echo "**************************************************"
