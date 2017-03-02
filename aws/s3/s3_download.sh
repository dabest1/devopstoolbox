#!/bin/bash
################################################################################
# Purpose:
#     Download data from AWS S3.
################################################################################

version="1.0.1"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

# Functions.

shopt -s expand_aliases
alias die='error_exit "ERROR in $0: line $LINENO:"'

# Usage.
usage() {
    echo "Usage:"
    echo "    $script_name aws_profile s3_bucket_path dir_target"
    echo
    echo "Example:"
    echo "    $script_name aws_restore s3://bucket/mongodb/hostname/20160101T010101Z.monthly /backups/restore"
    exit 1
}

error_exit() {
    echo "$@" >&2
    exit 78
}

set -o pipefail
set -o errtrace
trap 'rc=$? && [[ $rc -ne 78 ]] && error_exit "ERROR in $0: line $LINENO: exit code $rc." || exit 78' ERR
trap 'error_exit "ERROR in $0: Received signal SIGHUP."' SIGHUP
trap 'error_exit "ERROR in $0: Received signal SIGINT."' SIGINT
trap 'error_exit "ERROR in $0: Received signal SIGTERM."' SIGTERM

aws_profile="$1"
s3_bucket_path="$2"
dir_target="$3"

if [[ $# -ne 3 ]]; then
    usage
fi

if ! echo "$s3_bucket_path" | grep -q '/$'; then
    s3_bucket_path="$s3_bucket_path/"
fi

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
aws --profile "$aws_profile" s3 sync "$s3_bucket_path" "$dir_target"
rc=$?
if [[ $rc -ne 0 ]]; then die "Download from S3 failed."; fi

echo "**************************************************"
echo "* Time finished: $(date -u +'%FT%TZ')"
echo "**************************************************"
