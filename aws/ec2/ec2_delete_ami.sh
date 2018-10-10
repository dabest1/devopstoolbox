#!/bin/bash

# Purpose:
#     Deregisters EBS-backed AMI (Amazon Machine Image) and deletes the snapshot(s).
# Usage:
#     Run script with --help option to get usage.

version="1.1.0"

set -E
set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

shopt -s expand_aliases
alias die='error_exit "ERROR in $0: line $LINENO:"'

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

error_exit() {
    echo "$@" >&2
    exit 77
}
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

get_image_id() {
    local ami_name
    local image_id

    ami_name="$1"

    image_id="$(aws --profile "$profile" $region_opt ec2 describe-images --filters "Name=name,Values=$ami_name" --query 'Images[].ImageId' --output text)"
    if [[ $? -ne 0 || ! $image_id ]]; then
        die "Failure getting image ID."
    fi

    echo "$image_id"
}

get_snapshots() {
    local image_id
    local snapshot_ids

    image_id="$1"

    snapshot_ids="$(aws --profile "$profile" $region_opt ec2 describe-images --image-id "$image_id" --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text)"
    if [[ $? -ne 0 ]]; then
        die "Failure getting AMI snapshots."
    fi

    echo "$snapshot_ids"
}

deregister_ami() {
    local image_id

    image_id="$1"

    aws --profile "$profile" $region_opt ec2 deregister-image --image-id "$image_id"
    if [[ $? -ne 0 ]]; then
        die "Failure deregistering AMI."
    fi
}

delete_snapshot() {
    local snapshot_id

    snapshot_id="$1"

    aws --profile "$profile" $region_opt ec2 delete-snapshot --snapshot-id "$snapshot_id"
    if [[ $? -ne 0 ]]; then
        die "Failure deleting snapshot."
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
