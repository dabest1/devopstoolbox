#!/bin/bash
################################################################################
# Purpose:
#     Gather info from MongoDB host.
# Usage:
#     cat mongodb_get_host_info.sh | ssh myusername@myhost
################################################################################

version="1.0.0"


cmd="hostname"
echo "$cmd"
$cmd
echo

cmd="uname -a"
echo "$cmd"
$cmd
echo

cmd="cat /etc/issue"
echo "$cmd"
$cmd
echo

cmd="df -h"
echo "$cmd"
$cmd
echo

cmd="free -m"
echo "$cmd"
$cmd
echo

cmd="mongod --version"
echo "$cmd"
$cmd
echo
