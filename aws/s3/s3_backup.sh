#!/bin/bash
################################################################################
# Purpose:
#     Copy backup to AWS S3 and manage the number of backups retained on S3.
################################################################################

# Version.
version="1.0.3"

start_time="$(date -u +'%F %T %Z')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

if [[ $# -ne 2 ]]; then
    echo 'Usage:'
    echo '    $script_name dir_to_upload s3_bucket_path'
    echo 'Example:'
    echo '    $script_name /backups/20160101T010101Z.monthly s3://bucket/mongodb/hostname/'
    exit 1
fi
dir_to_upload="$1"
s3_bucket_path="$2"
if ! echo "$s3_bucket_path" | grep -q '/$'; then
    s3_bucket_path="$s3_bucket_path/"
fi
s3_bucket_sync_path="$s3_bucket_path$(basename "$dir_to_upload")"

# Load configuration settings.
source "$config_path"

s3cmd="aws --profile $aws_profile s3"
backup_types="daily weekly monthly yearly"

# Redirect stderr into error log, stdout and stderr into log.
log="${log:-/tmp/s3backup.log}"
log_err="${log_err:-/tmp/s3backup.err}"
rm "$log" "$log_err" 2> /dev/null
exec 1> "$log" 2> "$log" 2> "$log_err"

echo "**************************************************"
echo "* Upload Backup to S3"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "Directory to upload: $dir_to_upload"
echo "S3 Bucket path: $s3_bucket_path"

echo
echo 'Create md5 check sums.'
cd "$dir_to_upload" || exit 1
find . -type f | grep -v '[.]log$' | grep -v '[.]err$' | sort | xargs md5sum > md5sum.txt

echo
echo 'List of backups on S3, before upload:'
s3_backup_list=$($s3cmd ls "$s3_bucket_path" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)
echo "$s3_backup_list"

echo
echo 'Upload to S3:'
echo "Command:" $s3cmd sync "$dir_to_upload" "$s3_bucket_sync_path"
$s3cmd sync "$dir_to_upload" "$s3_bucket_sync_path"
rc=$?
if [[ $rc -ne 0 ]]; then
    echo 'Error: Upload to S3 failed.'
    exit $rc
fi

echo
echo 'List of backups on S3, before delete:'
s3_backup_list=$($s3cmd ls "$s3_bucket_path" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)
echo "$s3_backup_list"

s3_backup_list="$(echo "$s3_backup_list" | sort -r)"
echo
echo 'Delete old backups from S3:'
for backup_type in $backup_types; do
    if [[ $backup_type == 'daily' ]]; then
        backup_list="$(echo "$s3_backup_list" | grep '[.]daily')"
        num_bkups=$num_daily_bkups
    elif [[ $backup_type == 'weekly' ]]; then
        backup_list="$(echo "$s3_backup_list" | grep '[.]weekly')"
        num_bkups=$num_weekly_bkups
    elif [[ $backup_type == 'monthly' ]]; then
        backup_list="$(echo "$s3_backup_list" | grep '[.]monthly')"
        num_bkups=$num_monthly_bkups
    elif [[ $backup_type == 'yearly' ]]; then
        backup_list="$(echo "$s3_backup_list" | grep '[.]yearly')"
        num_bkups=$num_yearly_bkups
    fi
    num_bkups=$((num_bkups + 1))
    backup_delete="$(echo "$backup_list" | sed -n "${num_bkups},100p")"
    for backup in $backup_delete; do
        echo "delete backup: $backup"
        $s3cmd rm --recursive --quiet "$s3_bucket_path$backup"
    done
done

echo
echo 'List of backups on S3, after delete:'
s3_backup_list=$($s3cmd ls "$s3_bucket_path" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)
echo "$s3_backup_list"
echo

echo "**************************************************"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"

if [[ -s $log_err ]]; then
    exit 1
fi
