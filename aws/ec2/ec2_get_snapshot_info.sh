#!/bin/bash

# Purpose:
#     Provides information about AWS EC2 snapshot.
#     Multiple snapshots can be displayed if wildcard is used.
# Usage:
#     Run script with --help option to get usage.

version="1.0.2"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

name="$1"
profile="${AWS_PROFILE:-default}"

if [[ $1 == "--help" ]]; then
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [name|snapshot_id]"
    echo "    or"
    echo "    $script_name 'partial_name*'"
    exit 1
fi

echo "profile: $profile"
if echo "$name" | grep -q "snap-"; then
    SnapshotIds="$name"
else
    # If name is not supplied, then we want all instances.
    if [[ -z $name ]]; then
        SnapshotIds=$(aws --profile "$profile" ec2 describe-snapshots --owner-ids "self" --query 'Snapshots[].SnapshotId' --output text)
    else
        SnapshotIds=$(aws --profile "$profile" ec2 describe-snapshots --owner-ids "self" --filters "Name=tag:Name, Values=$name" --query 'Snapshots[].SnapshotId' --output text)
    fi
fi
if [[ -z $SnapshotIds ]]; then
    exit 1
fi

echo
echo "SnapshotId Snapshot.State VolumeId InstanceId Name AvailabilityZone InstanceType State.Name"
for SnapshotId in $SnapshotIds; do
    result=$(aws --profile "$profile" ec2 describe-snapshots --snapshot-ids "$SnapshotId" --output json)
    SnapshotId=$(echo "$result" | awk -F'"' '/"SnapshotId":/ {print $4}')
    Snapshot_State=$(echo "$result" | awk -F'"' '/"State":/ {print $4}')
    VolumeId=$(echo "$result" | awk -F'"' '/"VolumeId":/ {print $4}')

    exec 3>&1 4>&2 # Set up extra file descriptors.
    result=$( { aws --profile "$profile" ec2 describe-volumes --volume-ids "$VolumeId" --query 'Volumes[].Attachemnts.[InstanceId, State]' --output text | cat - 2>&4 1>&3; } 2>&1 )
    exec 3>&- 4>&- # Release the extra file descriptors.
    if echo "$result" | grep -q "The volume '.*' does not exist."; then
        InstanceId="VOLUME_DOES_NOT_EXIST"
    else
        echo "Debug: $result"
    fi
    echo "$SnapshotId $Snapshot_State $VolumeId $InstanceId"
done
