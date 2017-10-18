#!/bin/bash
################################################################################
# Purpose:
#     Capture essential info before host reboot.
# Usage:
#     Run script with --help option to get usage.
################################################################################

version="1.0.0"

set -o pipefail
script_name="$(basename "$0")"

host=$1

usage() {
    echo "Usage:"
    echo "    $script_name hostname"
    echo
    echo "Example:"
    echo "    $script_name my_host"
    exit 1
}

if [[ $1 == "--help" || -z $host ]]; then
    usage
fi

ssh $host 'echo "ps -ef"; sudo ps -ef; echo; echo "ss -na"; sudo ss -na; echo; echo "cat /etc/mtab"; cat /etc/mtab' > $host.log
