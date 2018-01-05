#!/bin/bash

# Purpose:
#     Deregisters EBS-backed AMI (Amazon Machine Image) and deletes the snapshot(s).
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

usage() {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [--profile profile] [--region region] {ami_name | image_name}"
    echo
    echo "Description:"
    echo "    --profile          Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE variable."
    echo "    --region           Use a specified region instead of region from configuration or environment setting."
    echo "    -h, --help         Display this help."
    exit 1
}

get_image_id() {
    local ami_name
    local image_id
    local rc

    ami_name="$1"

    image_id="$(aws --profile "$profile" $region_opt ec2 describe-images --filters "Name=name,Values=$ami_name" --query 'Images[].ImageId' --output text)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failure getting image status." 1>&2
        exit 1
    fi

    echo "$image_id"
}

get_snapshots() {
    local image_id
    local snapshot_ids
    local rc

    image_id="$1"

    snapshot_ids="$(aws --profile "$profile" $region_opt ec2 describe-images --image-id "$image_id" --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failure getting AMI snapshots." 1>&2
        exit 1
    fi

    echo "$snapshot_ids"
}

deregister_ami() {
    local image_id
    local rc

    image_id="$1"

    aws --profile "$profile" $region_opt ec2 deregister-image --image-id "$image_id"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failure deregistering AMI." 1>&2
        exit 1
    fi
}

delete_snapshot() {
    local snapshot_id
    local rc

    snapshot_id="$1"

    aws --profile "$profile" $region_opt ec2 delete-snapshot --snapshot-id "$snapshot_id"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failure deleting snapshot." 1>&2
        exit 1
    fi
}

while test -n "$1"; do
    case "$1" in
    -h|--help)
        usage
        ;;
    --profile)
        shift
        profile="$1"
        shift
        ;;
    --region)
        shift
        region="$1"
        region_opt="--region=$region"
        shift
        ;;
    -w|--wait)
        wait_to_be_deleted="yes"
        shift
        ;;
    *)
        ami_name="$1"
        shift
    esac
done

if [[ -z $ami_name ]]; then
    usage
fi

echo "ami_name: $ami_name"

image_id="$(get_image_id "$ami_name")"
echo "image_id: $image_id"
echo

echo "Snapshot IDs:"
snapshot_ids="$(get_snapshots "$image_id")"
echo "$snapshot_ids"
echo

echo "Deregistering AMI."
deregister_ami "$image_id"
echo

echo "Deleting snapshot(s)."
for snapshot_id in $snapshot_ids; do
    delete_snapshot "$snapshot_id"
done
