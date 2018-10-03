#!/usr/bin/env bash
################################################################################
# Purpose:
#     Transfer backups in S3 from one AWS account to another.
#     Directory structure in S3:
#         s3://bucket/database_type/hostname/timestamp.backup_type/*
################################################################################

version="1.2.0"

start_time="$(date -u +'%F %T %Z')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

# Load configuration settings.
source "$config_path"

s3cmd="aws --profile $aws_profile s3"

shopt -s expand_aliases
alias die='error_exit "ERROR: ${0}(@$LINENO):"'

function usage {
    echo "Usage:"
    echo "    $script_name"
    echo
    echo "Example:"
    echo "    $script_name"
    echo '
Prerequisites:

    Source bucket needs to have the following bucket policy. Replace source_bucket, destination_account, and destination_username with appropriate values.
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowAll",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::destination_account:user/destination_username"
                },
                "Action": "s3:*",
                "Resource": [
                    "arn:aws:s3:::source_bucket",
                    "arn:aws:s3:::source_bucket/*"
                ]
            }
        ]
    }

    A user with the following policy is needed in destination account. Replace source_bucket and destination_bucket with appropriate values.
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:AbortMultipartUpload",
                    "s3:GetBucketLocation",
                    "s3:GetObject",
                    "s3:GetObjectAcl",
                    "s3:GetObjectTagging",
                    "s3:GetObjectTorrent",
                    "s3:GetObjectVersion",
                    "s3:GetObjectVersionAcl",
                    "s3:GetObjectVersionTagging",
                    "s3:GetObjectVersionTorrent",
                    "s3:ListBucket",
                    "s3:ListBucketMultipartUploads",
                    "s3:ListBucketVersions",
                    "s3:ListMultipartUploadParts",
                    "s3:PutObject",
                    "s3:PutObjectTagging"
                ],
                "Resource": [
                    "arn:aws:s3:::destination_bucket",
                    "arn:aws:s3:::destination_bucket/*",
                    "arn:aws:s3:::source_bucket",
                    "arn:aws:s3:::source_bucket/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:DeleteObject"
                ],
                "Resource": [
                    "arn:aws:s3:::source_bucket/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:ListAllMyBuckets"
                ],
                "Resource": "*"
            }
        ]
    }'
    exit 1
}

error_exit() {
    echo
    echo "$@" >&2
    exit 1
}
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

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
if [[ $? -ne 0 || ! $s3_host_list ]]; then
    die "Listing in S3 source bucket has failed."
fi
echo "$s3_host_list"

echo
for host in $s3_host_list; do
    echo "$host source:"
    s3_backup_list_source="$($s3cmd ls "${s3uri_source}${host}/" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)"
    echo "$s3_backup_list_source"
    echo

    echo "$host target:"
    s3_backup_list_target="$($s3cmd ls "${s3uri_target}${host}/" | awk -F' |/' '/ PRE / {print $(NF-1)}' | sort)"
    echo "$s3_backup_list_target"

    # Skip the most recent backup, as the upload to S3 source location may not have completed.
    s3_backup_list_source="$(echo "$s3_backup_list_source" | sort -r | sed '1d' | sort)"

    for s3_backup in $s3_backup_list_source; do
        echo
        if ! echo "$s3_backup_list_target" | grep -q "$s3_backup"; then
            echo "Transfer: ${s3uri_source}${host}/$s3_backup"
            $s3cmd cp --recursive --quiet "${s3uri_source}${host}/$s3_backup" "${s3uri_target}${host}/$s3_backup"
            if [[ $? -ne 0 ]]; then
                die "S3 copy failed."
            fi

            # Delete from source bucket after copying to target bucket.
            echo "Delete: ${s3uri_source}${host}/$s3_backup"
            $s3cmd rm --recursive --quiet "${s3uri_source}${host}/$s3_backup"
            if [[ $? -ne 0 ]]; then
                die "Deleting from S3 source bucket has failed."
            fi
        else
            # Skip transfer if the timestamped directory is in both buckets.
            echo "Skip transfer: ${s3uri_source}${host}/$s3_backup"
        fi
    done
    echo
done

echo "**************************************************"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"
