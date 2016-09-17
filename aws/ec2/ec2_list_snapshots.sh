#!/bin/bash

# Purpose:
#     Provides a list of one or more AWS EC2 snapshots.
#     Multiple snapshots can be displayed if partial name with wildcard is
#     supplied.
# Usage:
#     Run script with --help option to get usage.

version="1.0.3"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"
name=$1

function usage {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [name]"
    echo "    or"
    echo "    $script_name 'partial_name*'"
    exit 1
}

if [[ $1 == "--help" ]]; then
    usage
fi

echo "profile: $profile"
if echo "$name" | grep -q "snap-"; then
    snapshot_ids="$name"
else
    # If name is not supplied, then we want all snapshots.
    if [[ -z $name ]]; then
        snapshot_ids=$(aws --profile "$profile" ec2 describe-snapshots --owner-ids "self" --query 'Snapshots[].SnapshotId' --output text)
    else
        snapshot_ids=$(aws --profile "$profile" ec2 describe-snapshots --owner-ids "self" --filters "Name=tag:Name, Values=$name" --query 'Snapshots[].SnapshotId' --output text)
    fi
fi
if [[ -z $snapshot_ids ]]; then
    exit 1
fi

echo
aws --profile "$profile" ec2 describe-snapshots --snapshot-ids $snapshot_ids --output text
