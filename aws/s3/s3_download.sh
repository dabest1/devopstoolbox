#!/bin/bash
################################################################################
# Purpose:
#     Download data from AWS S3.
################################################################################

version="1.0.0"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

aws_profile="$1"
s3_bucket_path="$2"
dir_target="$3"

if ! echo "$s3_bucket_path" | grep -q '/$'; then
    s3_bucket_path="$s3_bucket_path/"
fi

s3cmd="aws --profile $aws_profile s3"

usage() {
    echo "Usage:"
    echo "    $script_name aws_profile s3_bucket_path dir_target"
    echo
    echo "Example:"
    echo "    $script_name aws_restore s3://bucket/mongodb/hostname/20160101T010101Z.monthly /backups/restore"
    exit 1
}

if [[ $# -ne 3 ]]; then
    usage
fi

set -E
set -o pipefail

echo "**************************************************"
echo "* Download from S3"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "S3 Bucket path: $s3_bucket_path"
echo "Target directory: $dir_target"

echo
if [[ ! -d $dir_target ]]; then
    mkdir "$dir_target"
fi
echo 'Download from S3:'
$s3cmd sync "$s3_bucket_path" "$dir_target"

#echo
#echo 'Create md5 check sums.'
#cd "$dir_to_upload" || exit 1
#find . -type f | grep -v '[.]log$' | grep -v '[.]err$' | grep -v 'md5sum.txt' | sort | xargs md5sum > md5sum.txt

echo "**************************************************"
echo "* Time finished: $(date -u +'%FT%TZ')"
echo "**************************************************"
