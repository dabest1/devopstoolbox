#!/bin/bash
################################################################################
# Purpose:
#     Add public key to SSH authorized_keys file.
#
# Usage:
#     add_public_key.sh host1 [host2 ...]
################################################################################

version="1.0.1"

# Hosts on which to add public key.
hosts=$@
# User to which to add public key. Current user or SSH config setting will control which user is used for SSH connectivity.
user="your_username"
public_key_file=~/.ssh/your_public_key.pub

public_key="$(cat "$public_key_file")"

for host in $hosts; do
    echo "host: $host"
    cat <<HERE_DOCUMENT | ssh "$host"
if ! sudo grep -q "$public_key" /home/"$user"/.ssh/authorized_keys; then
    echo "$public_key" | sudo tee -a /home/"$user"/.ssh/authorized_keys > /dev/null
fi
HERE_DOCUMENT
done
