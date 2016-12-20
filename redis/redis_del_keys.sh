#!/bin/bash

# Purpose:
#     Delete keys from Redis. Keys are supplied in a file, with newline delimiter.

if [[ $# -ne 3 ]]; then
    echo "Usage:"
    echo "    $0 host port file_keys > file.log"
    echo
    echo "Example:"
    echo "    $0 myhost 7000 keys.out > del_keys.log"
    exit 1
fi

host="$1"
port="$2"
file_keys="$3"
sleep_time_us=10000

while read key; do
    echo redis-cli -c -h "$host" -p "$port" del "$key"
    redis-cli -c -h "$host" -p "$port" del "$key"
    usleep "$sleep_time_us"
done <"$file_keys"
