#!/bin/bash

# Purpose:
#     Change AWS instance type. Instance may optionally be stopped and started.
# Usage:
#     Run script with --help option to get usage.

version="1.2.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
log="$script_dir/${script_name/.sh/.log}"

profile="${AWS_PROFILE:-default}"

function usage {
    cat <<USAGE
Usage:
    [export AWS_PROFILE=profile]
    $script_name [--profile profile] [--region region] [-s] [-n] {name | instance_id} instance_type

    Example:
        $script_name myhost m3.medium

    Description:
        -n, --no-prompt     No confirmation prompt.
        --profile           Use a specified profile from your AWS credential file, otherwise get it from AWS_PROFILE environment variable.
        --region            Use a specified region instead of region from configuration or environment setting.
        -s, --stop-start    Stop instance, change instance type, and start instance.
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
        region_optws="--region $region"
        shift
        ;;
    -n|--no-prompt)
        no_prompt_option="-n"
        shift
        ;;
    -s|--stop-start)
        do_stop_start="yes"
        shift
        ;;
    *)
        name="$1"
        shift
        instance_type="$1"
        shift
    esac
done

if [[ -z $name || -z $instance_type ]]; then
    echo "Error: Instance name or type is missing."
    echo
    usage
fi

echo >> $log
echo >> $log
date +'%F %T %z' >> $log
echo "profile: $profile" | tee -a $log
if echo "$name" | grep -q '^i-'; then
    instance_id="$name"
else
    echo "name: $name" | tee -a $log
    instance_id=$(aws --profile "$profile" $region_opt ec2 describe-instances --filters "Name=tag:Name, Values=$name" --query 'Reservations[].Instances[].[InstanceId]' --output text)
fi
echo "instance_id: $instance_id" | tee -a $log
if [[ -z $instance_id || -z $instance_type ]]; then
    echo "Error."
    exit 1
fi
echo

if [[ $do_stop_start == "yes" ]]; then
    echo "Stop instance..."
    "$script_dir"/ec2_stop_instance.sh --profile "$profile" $region_optws $no_prompt_option -w "$instance_id"
    rc=$?
    if [[ $rc -gt 0 ]]; then
        echo "Error: Instance could not be stopped."
        exit 1
    fi
    echo
fi

echo "Modify instance type..."
rc=0
if [[ $instance_type == "m3.medium" ]]; then
    aws --profile "$profile" $region_opt ec2 modify-instance-attribute --instance-id "$instance_id" --no-ebs-optimized
    rc=$?
fi
aws --profile "$profile" $region_opt ec2 modify-instance-attribute --instance-id "$instance_id" --instance-type "$instance_type"
rc=$(($? + $rc))
if [[ $rc -gt 0 ]]; then
    echo "Error: Instance type could not be changed."
    exit 1
fi
echo "Done."
echo

if [[ $do_stop_start == "yes" ]]; then
    echo "Start instance..."
    "$script_dir"/ec2_start_instance.sh --profile "$profile" $region_optws -n -w "$instance_id"
    rc=$?
    if [[ $rc -gt 0 ]]; then
        echo "Error: Instance could not be started."
        exit 1
    fi
fi
