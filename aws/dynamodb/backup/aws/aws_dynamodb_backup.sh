#!/bin/bash
################################################################################
# Purpose:
#     Takes a backup of DynamoDB tables using AWS DynamoDB backup.
# Usage:
#     Run script with --help option to get usage.
################################################################################

version="1.0.0"

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
    echo
    echo "Description:"
    echo "    Takes a backup of DynamoDB tables using AWS DynamoDB backup."
    echo "    "
    echo "    Options:"
    echo "    --version                  Display script version."
    echo "    --help                     Display this help."
    exit 1
}

error_exit() {
    echo "$@" >&2
    exit 77
}

backup() {
    for table in $tables_backup; do
        date -u +'start: %FT%TZ'
        echo "Table: $table"
        aws --profile "$aws_profile" --region "$region" dynamodb create-backup --table-name "$table" --backup-name "$table.$bkup_date.$bkup_type"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            die "aws command failed."
        fi
        echo
    done
    date -u +'backup finish: %FT%TZ'
    echo
}

purge_old_backups() {
    echo "Purge old backups..."
    for table in $tables_backup; do
        echo
        list_of_bkups="$(aws --profile "$aws_profile" --region "$region" dynamodb list-backups --table-name "$table" | jq "[ .BackupSummaries[] | select(.BackupStatus | contains(\"AVAILABLE\")) | select(.BackupName | contains(\"$bkup_type\")) ]" | jq 'sort_by(.BackupCreationDateTime)')"
        if [[ ! -z "$list_of_bkups" ]]; then
            while [[ "$(echo "$list_of_bkups" | jq 'length')" -gt $num_bkups ]]; do
                old_bkup="$(echo "$list_of_bkups" | jq -r '.[0].BackupName')"
                old_bkup_arn="$(echo "$list_of_bkups" | jq -r '.[0].BackupArn')"
                echo "Deleting old backup: $old_bkup"
echo $old_bkup_arn
                aws --profile "$aws_profile" --region "$region" dynamodb delete-backup --backup-arn "$old_bkup_arn"
                if [[ $? -ne 0 ]]; then die "Backup deletion failed."; fi
                # Need to rate limit to 10 delete-backup calls per second.
                sleep 0.1
                list_of_bkups="$(aws --profile "$aws_profile" --region "$region" dynamodb list-backups --table-name "$table" | jq "[ .BackupSummaries[] | select(.BackupStatus | contains(\"AVAILABLE\")) | select(.BackupName | contains(\"$bkup_type\")) ]" | jq 'sort_by(.BackupCreationDateTime)')"
            done
        fi
    done
    echo
    echo "Done."
    echo
}

set -E
set -o pipefail
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

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

# Load configuration settings.
source "$config_path"

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

#select_backup_type
bkup_type="daily"
num_bkups=$num_daily_bkups

echo "All tables in the region:"
tables_all="$(aws --profile "$aws_profile" --region "$region" dynamodb list-tables --output text | awk '{print $2}')"
echo "$tables_all"
echo

echo "Tables selected for backup:"
tables_backup="$(echo "$tables_all" | egrep "$tables_include" | egrep -v "$tables_exclude")"
echo "$tables_backup"
echo

backup

purge_old_backups

echo "**************************************************"
echo "* Time finished: $(date -u +'%FT%TZ')"
echo "**************************************************"
