#!/bin/bash

# Purpose:
#     Delete AWS RDS instance.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

profile="${AWS_PROFILE:-default}"

usage() {
    echo "Usage:"
    echo "    export AWS_PROFILE=profile"
    echo
    echo "    $script_name [--profile profile] [--region region] [-n] [-w] {instance-name}..."
    echo
    echo "Description:"
    echo "    --profile          Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE variable."
    echo "    --region           Use a specified region instead of region from configuration or environment setting."
    echo "    -n, --no-prompt    No confirmation prompt."
    echo "    -w, --wait         Wait for 'deleted' state before finishing."
    echo "    -h, --help         Display this help."
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
    -n|--no-prompt)
        do_not_prompt="yes"
        shift
        ;;
    -w|--wait)
        wait_for_deleted="yes"
        shift
        ;;
    *)
        if [[ -z $names ]]; then
            names="$1"
        else
            names="$names $1"
        fi
        shift
    esac
done

if [[ -z $names ]]; then
    usage
fi

echo >> "$log"
echo >> "$log"
date +'%F %T %z' >> "$log"
echo "profile: $profile" | tee -a "$log"

for name in $names; do
    echo | tee -a "$log"
    aws --profile "$profile" $region_opt rds describe-db-instances --db-instance-identifier "$name" --output json | tee -a "$log"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Error: Failed to query AWS." | tee -a "$log"
        exit 1
    fi

    if [[ ! $do_not_prompt ]]; then
        echo -n 'Are you sure that you want this instance deleted? y/n: '
        read -r yn
        if [[ $yn != y ]]; then
            echo 'Aborted!' | tee -a "$log"
            exit 1
        fi
        echo
    fi

    echo "Delete instance..." | tee -a "$log"
    aws --profile "$profile" $region_opt rds delete-db-instance --db-instance-identifier "$name" --output json | tee -a "$log"
    state="deleting"
    while [[ $state = "deleting" ]] && [[ $wait_for_deleted == yes ]]; do
        state="$(aws --profile "$profile" $region_opt rds describe-db-instances --db-instance-identifier "$name" --query 'DBInstances[0].DBInstanceStatus' --output json 2> /dev/null | jq -r '.')"
        echo -n "."
        sleep 1
    done
    echo 'Done.' | tee -a "$log"
done
