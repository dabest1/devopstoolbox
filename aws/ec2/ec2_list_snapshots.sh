#!/usr/bin/env bash

# Purpose:
#     Provides a list of one or more AWS EC2 snapshots.
#     Multiple snapshots can be displayed if partial name with wildcard is
#     supplied.
# Usage:
#     Run script with --help option to get usage.

version="1.1.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

function usage {
    cat <<USAGE
Usage:
    [export AWS_PROFILE=profile]
    $script_name [--profile profile] [--region region] [name | 'partial_name*']

    Example:
        $script_name
        $script_name snap-0123456789abcdef0
        $script_name 'snap-01234*'

    Description:
        --profile           Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE environment variable.
        --region            Use a specified region instead of region from configuration or environment setting.
        -h, --help          Display this help.
USAGE
    exit 1
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
    *)
        name="$1"
        shift
    esac
done

echo "profile: $profile"
if echo "$name" | grep -q "snap-"; then
    snapshot_ids="$name"
else
    # If name is not supplied, then we want all snapshots.
    if [[ -z $name ]]; then
        snapshot_ids=$(aws --profile "$profile" $region_opt ec2 describe-snapshots --owner-ids "self" --query 'Snapshots[].SnapshotId' --output text)
    else
        snapshot_ids=$(aws --profile "$profile" $region_opt ec2 describe-snapshots --owner-ids "self" --filters "Name=tag:Name, Values=$name" --query 'Snapshots[].SnapshotId' --output text)
    fi
fi
if [[ -z $snapshot_ids ]]; then
    exit 1
fi

echo
aws --profile "$profile" $region_opt ec2 describe-snapshots --snapshot-ids $snapshot_ids --output text
