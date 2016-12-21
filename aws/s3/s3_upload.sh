#!/bin/bash
################################################################################
# Purpose:
#     Upload data to AWS S3.
################################################################################

version="1.0.0"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

aws_profile="$1"
dir_source="$2"
s3_bucket_path="$3"

if ! echo "$s3_bucket_path" | grep -q '/$'; then
    s3_bucket_path="$s3_bucket_path/"
fi

s3cmd="aws --profile $aws_profile s3"

usage() {
    echo "Usage:"
    echo "    $script_name aws_profile dir_source s3_bucket_path"
    echo
    echo "Example:"
    echo "    $script_name aws_backup /backups/20160101T010101Z.monthly s3://bucket/mongodb/hostname/20160101T010101Z.monthly"
    exit 1
}

if [[ $# -ne 3 ]]; then
    usage
fi

set -E
set -o pipefail

echo "**************************************************"
echo "* Upload to S3"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "Source directory: $dir_source"
echo "S3 Bucket path: $s3_bucket_path"

echo
echo 'Create md5 check sums.'
cd "$dir_source" || exit 1
find . -type f | grep -v '[.]log$' | grep -v '[.]err$' | grep -v 'md5sum.txt' | sort | xargs md5sum > md5sum.txt

echo
echo 'Upload to S3:'
$s3cmd sync "$dir_source" "$s3_bucket_path"

echo "**************************************************"
echo "* Time finished: $(date -u +'%FT%TZ')"
echo "**************************************************"
