#!/bin/bash
################################################################################
# Purpose:
#     Manage number of archives kept on AWS S3 by deleting older archives.
################################################################################

version="1.0.0"

start_time="$(date -u +'%F %T %Z')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"
log="$script_dir/${script_name/.sh/.log}"
log_err="$script_dir/${script_name/.sh/.err}"

# Load configuration settings.
source "$config_path"

if ! echo "$s3_bucket_path" | grep -q '/$'; then
    s3_bucket_path="$s3_bucket_path/"
fi

s3cmd="aws --profile $aws_profile --region "$s3_region" s3"
backup_types="daily weekly monthly yearly"

function usage {
    echo "Usage:"
    echo "    $script_name"
    echo
    echo "Example:"
    echo "    $script_name"
    exit 1
}

if [[ $# -ne 0 ]]; then
    usage
fi

# Redirect stderr into error log, stdout and stderr into log.
exec 1> "$log" 2> "$log" 2> "$log_err"

echo "**************************************************"
echo "* Manage archives on S3 - delete old backups"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "S3 Bucket path: $s3_bucket_path"

echo
echo "Hosts:"
s3_host_list=$($s3cmd ls "$s3_bucket_path" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)
echo "$s3_host_list"

echo
for host in $s3_host_list; do
    echo $host:
    s3_backup_list=$($s3cmd ls "$s3_bucket_path$host/" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)
    echo "$s3_backup_list"
    echo
    for backup_type in $backup_types; do
        backup_list="$(echo "$s3_backup_list" | grep "[.]$backup_type" | sort -r)"
        if [[ $backup_type == 'daily' ]]; then
            num_bkups=$num_daily_bkups
        elif [[ $backup_type == 'weekly' ]]; then
            num_bkups=$num_weekly_bkups
        elif [[ $backup_type == 'monthly' ]]; then
            num_bkups=$num_monthly_bkups
        elif [[ $backup_type == 'yearly' ]]; then
            num_bkups=$num_yearly_bkups
        fi
        num_bkups=$((num_bkups + 1))
        backup_delete="$(echo "$backup_list" | sed -n "${num_bkups},100p")"
        for backup in $backup_delete; do
            echo "delete backup: $backup"
            $s3cmd rm --recursive --quiet "$s3_bucket_path$host/$backup"
        done
    done
    echo
done

echo "**************************************************"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"

if [[ -s $log_err ]]; then
    exit 1
fi
