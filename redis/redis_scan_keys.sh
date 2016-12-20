#!/bin/bash

# Purpose:
#     Script to scan Redis for keys that match a pattern.

if [[ $# -ne 3 ]]; then
    echo "Usage:"
    echo "    $0 host port pattern > keys.out"
    echo
    echo "Example:"
    echo "    $0 myhost 7000 'somekey*' > keys.out"
    exit 1
fi

host="$1"
port="$2"
pattern="$3"

cursor=-1
keys=""

while [[ $cursor -ne 0 ]]; do
    if [[ $cursor -eq -1 ]]; then
        cursor=0
    fi

    reply="$(redis-cli -c -h "$host" -p "$port" SCAN "$cursor" MATCH "$pattern")"
    cursor="$(head -1 <<<"$reply")"
    keys="$(sed '1d' <<<"$reply")"

    echo "$keys"
done
