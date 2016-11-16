#!/bin/bash
################################################################################
# Purpose:
#     Add public key to SSH authorized_keys file.
#
# Usage:
#     add_public_key.sh host1 [host2 ...]
################################################################################

version="1.0.0"

hosts=$@
user="your_username"
public_key_file=~/.ssh/your_public_key.pub

public_key="$(cat "$public_key_file")"

for host in $hosts; do
    echo "host: $host"
    cat <<HERE_DOCUMENT | ssh "$user"@"$host"
if ! grep -q "$public_key" /home/"$user"/.ssh/authorized_keys; then
    echo "$public_key" >> /home/"$user"/.ssh/authorized_keys
fi
HERE_DOCUMENT
done
