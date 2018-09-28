#!/usr/bin/env bash
################################################################################
# Purpose:
#     Transfer backups in S3 from one AWS account to another.
#     Directory structure in S3:
#         s3://bucket/database_type/hostname/timestamp.backup_type/*
################################################################################

version="1.0.0"

start_time="$(date -u +'%F %T %Z')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

# Load configuration settings.
source "$config_path"

s3cmd="aws --profile $aws_profile s3"
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

if ! echo "$s3uri_source" | grep -q '/$'; then
    s3uri_source="$s3uri_source/"
fi
if ! echo "$s3uri_target" | grep -q '/$'; then
    s3uri_target="$s3uri_target/"
fi

echo "**************************************************"
echo "* Transfer backups between S3 buckets"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "S3 source: $s3uri_source"
echo "S3 target: $s3uri_target"

echo
echo "Hosts:"
s3_host_list="$($s3cmd ls "$s3uri_source" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)"
echo "$s3_host_list"

echo
for host in $s3_host_list; do
    echo "$host source:"
    s3_backup_list_source="$($s3cmd ls "$s3uri_source$host/" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)"
    echo "$s3_backup_list_source"
    echo

    echo "$host target:"
    s3_backup_list_target="$($s3cmd ls "$s3uri_target$host/" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)"
    echo "$s3_backup_list_target"
    echo

    # Skip the most recent backup, as the upload to S3 source location may not have completed.
    s3_backup_list_source="$(echo "$s3_backup_list_source" | sort -r | sed '1d' | sort)"

    for s3_backup in $s3_backup_list_source; do
        echo "Transfer: $s3_backup"
        if ! echo "$s3_backup_list_target" | grep -q "$s3_backup"; then
            $s3cmd cp --recursive "$s3uri_source$host/$s3_backup" "$s3uri_target$host/$s3_backup"
            rc=$?
            echo
            if [[ $rc -ne 0 ]]; then
                echo "Error: S3 copy failed!"
                exit 1
            fi

            # TODO: Delete in source bucket after copying to target bucket.
        else
            echo "Skipped transfer as this timestamped directory is in both buckets."
            echo
        fi
    done

    # for backup_type in $backup_types; do
    #     backup_list="$(echo "$s3_backup_list" | grep "[.]$backup_type" | sort -r)"
    #     if [[ $backup_type == 'daily' ]]; then
    #         num_bkups=$num_daily_bkups
    #     elif [[ $backup_type == 'weekly' ]]; then
    #         num_bkups=$num_weekly_bkups
    #     elif [[ $backup_type == 'monthly' ]]; then
    #         num_bkups=$num_monthly_bkups
    #     elif [[ $backup_type == 'yearly' ]]; then
    #         num_bkups=$num_yearly_bkups
    #     fi
    #     num_bkups=$((num_bkups + 1))
    #     #backup_delete="$(echo "$backup_list" | sed -n "${num_bkups},100p")"
    #     #for backup in $backup_delete; do
    #         #echo "delete backup: $backup"
    #         #$s3cmd rm --recursive --quiet "$s3_bucket_path$host/$backup"
    #     #done
    # done
    # echo
done

echo "**************************************************"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"
