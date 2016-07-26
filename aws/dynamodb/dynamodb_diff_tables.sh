#!/bin/bash

# Purpose:
#     Perform consistency check between two DynamoDB tables in different regions. Wrapper script for diff-tables utility.
# Usage:
#     Run script with --help option to get usage.

version="1.0.0"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

table="$1"
src_region="$2"
dst_region="$3"
segments="$4"

function usage {
    echo "Usage:"
    echo "    $script_name table soure_region destination_region [segments]"
    echo "Example:"
    echo "    $script_name Prod_MyTable us-east-1 us-west-2 5"
    exit 1
}

if [[ $1 == "--help" || -z $table || -z $src_region || -z $dst_region ]]; then
    usage
fi
if [[ -z $segments ]]; then
    segments=1
fi

cd "$script_dir" || exit 1
mkdir "$table.$dst_region"
cd "$table.$dst_region" || exit 1
rm -v *
for (( segment=0; segment<"$segments"; segment++ )); do
    echo "segment: $segment"
    diff-tables "$src_region/$table" "$dst_region/$table" --segments "$segments" --segment "$segment" --repair > "$table.$dst_region.$segment.log" &
done

wait
echo "Done."
echo

ls
echo
grep '\[discrepancies\]' "$table.$dst_region."*".log"
