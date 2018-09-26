#!/bin/bash

# Purpose:
#     Delete EC2 volume snapshot.
# Usage:
#     Run script with -h option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name snapshot_descr"
    echo
    echo "Description:"
    echo "    -h, --help      Show this help."
    exit 1
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
        ;;
    *)
        snapshot_descr="$1"
        shift
    esac
done
profile="${AWS_PROFILE:-default}"

if [[ -z $snapshot_descr ]]; then
    usage
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
echo "snapshot_descr: $snapshot_descr" | tee -a $log
echo | tee -a $log

result="$(aws --profile "$profile" ec2 describe-snapshots --filters "Name=description,Values=$snapshot_descr" --output json)"
rc=$?
if [[ $rc -ne 0 ]]; then
    echo 'Error getting snapshot information.' | tee -a $log
    exit 1
fi
echo $result | tee -a $log

snapshot_ids="$(echo $result | jq -r '.Snapshots[].SnapshotId')"

echo
echo "Delete snapshots..." | tee -a $log
echo "snapshot_ids: 
$snapshot_ids" | tee -a $log
for snapshot_id in $snapshot_ids; do
    aws --profile "$profile" ec2 delete-snapshot --snapshot-id "$snapshot_id"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo 'Error deleting snapshot.' | tee -a $log
        exit 1
    fi
done

echo 'Done.' | tee -a $log