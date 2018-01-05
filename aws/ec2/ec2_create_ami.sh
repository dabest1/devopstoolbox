#!/bin/bash

# Purpose:
#     Creates Amazon EBS-backed AMI (Amazon Machine Image).
# Usage:
#     Run script with --help option to get usage.

version="1.3.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

profile="${AWS_PROFILE:-default}"

usage() {
    echo "Usage:"
    echo "    $script_name [--profile profile] [--region region] [-t] [-s] [-w] {name | instance_id} image_name [description]"
    echo
    echo "Description:"
    echo "    --profile          Use a specified profile from your AWS credential file. Otherwise run `export AWS_PROFILE=profile` before this sript."
    echo "    --region           Use a specified region instead of region from configuration or environment setting."
    echo "    -t                 Tag the AMI based on EC2 instance tags."
    echo "    -s                 Tag the snapshots based on EC2 instance tags. Turns on -w option."
    echo "    -w, --wait         Wait for AMI to become available."
    echo "    -h, --help         Display this help."
    exit 1
}

get_instance_id() {
    local name
    local instance_id
    local rc

    name="$1"

    if echo "$name" | grep -q '^i-'; then
        instance_id="$name"
    else
        instance_id=$(aws --profile "$profile" $region_opt ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "Error: Failed to query AWS." 1>&2
            exit 1
        fi
    fi
    if [[ -z $instance_id ]]; then
        echo "Error: Instance was not found." 1>&2
        exit 1
    fi
    echo "$instance_id"
}

get_instance_tags() {
    local instance_id
    local tags
    local rc

    instance_id="$1"

    tags="$(aws --profile "$profile" ec2 describe-instances --instance-ids "$instance_id" --query 'Reservations[].Instances[].Tags[]' --output json)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failed to query AWS." 1>&2
        exit 1
    fi

    echo "$tags"
}

create_image() {
    local image_id
    local rc

    image_id="$(aws --profile "$profile" $region_opt ec2 create-image --instance-id "$instance_id" --name "$image_name" --description "$description" --output text)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failure during image creation." 1>&2
        exit 1
    fi

    echo "$image_id"
}

create_tags() {
    local resource
    local tags
    local rc

    resource="$1"
    tags="$2"

    aws --profile "$profile" $region_opt ec2 create-tags --resources "$resource" --tags "$tags"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failure during image tagging." 1>&2
        exit 1
    fi
}

get_image_status() {
    local image_id
    local image_status
    local rc

    image_id="$1"

    image_status="$(aws --profile "$profile" $region_opt ec2 describe-images --image-ids "$image_id" --query 'Images[].State' --output text)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failure getting image status." 1>&2
        exit 1
    fi

    echo "$image_status"
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
    -t)
        tag_ami="yes"
        shift
        ;;
    -s)
        tag_snapshot="yes"
        wait_for_available_status="yes"
        shift
        ;;
    -w|--wait)
        wait_for_available_status="yes"
        shift
        ;;
    *)
        name="$1"
        shift
        image_name="$1"
        shift
        description="$1"
        shift
    esac
done

if [[ -z $name || -z $image_name ]]; then
    usage
fi

echo "name: $name"
echo "image_name: $image_name"
echo "description: $description"
echo

instance_id="$(get_instance_id "$name")"

echo "Creating AMI."
image_id="$(create_image)"
echo "image_id: $image_id"
echo

if [[ $tag_ami = "yes" ]]; then
    echo "Getting tags:"
    tags="$(get_instance_tags "$instance_id")"
    echo "$tags"
    echo

    echo "Tagging AMI."
    create_tags "$image_id" "$tags"
    echo
fi

if [[ $wait_for_available_status = "yes" ]]; then
    echo "Waiting for AMI status to become available..."
    image_status=""
    while [[ $image_status != "available" ]]; do
        image_status="$(get_image_status "$image_id")"
        echo -n "."
        sleep 1
    done
    echo "Done."
    echo
fi

if [[ $tag_snapshot = "yes" ]]; then
    echo "Getting snapshot IDs:"
    snapshot_ids="$(get_snapshots "$image_id")"
    echo "$snapshot_ids"
    echo

    echo "Tagging snapshots."
    for snapshot_id in $snapshot_ids; do
        create_tags "$snapshot_id" "$tags"
    done
    echo
fi
