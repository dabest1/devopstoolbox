#!/bin/bash

# Purpose:
#    Delete AWS Volume.
# Usage:
#     Run script with no options to get usage.

version=1.0.1

volume_id="$1"
log='delete_volume.log'
profile="$AWS_PROFILE"

set -o pipefail
if [[ -z $volume_id ]]; then
    echo 'Usage:'
    echo '    script.sh volume_id'
    exit 1
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "volume_id: $volume_id" | tee -a $log

aws --profile "$profile" ec2 describe-volumes --volume-ids "$volume_id" --output table | tee -a $log

echo -n 'Are you sure that you want this volume deleted? y/n: '
read yn
if [[ $yn == y ]]; then
    echo "Deleting volume_id: $volume_id" | tee -a $log
    aws --profile "$profile" ec2 delete-volume --volume-id "$volume_id" | tee -a $log
else
    echo 'Aborted!' | tee -a $log
    exit 1
fi
