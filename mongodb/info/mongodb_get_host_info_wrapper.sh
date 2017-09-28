#!/bin/bash
################################################################################
# Purpose:
#     Wrapper script for mongodb_get_host_info.sh.
# Usage:
#     1. Edit mongodb_get_host_info_wrapper.sh.
#     2. ./mongodb_get_host_info_wrapper.sh &> logfile.txt
################################################################################

version="1.0.0"

ssh_user="ec2-user"
script="mongodb_get_host_info.sh"

hosts="myhost1
myhost2
myhost3"

for host in $hosts; do
    echo "$host:"
    cat "$script" | ssh "$ssh_user"@"$host"
    echo
    echo
    echo
done
