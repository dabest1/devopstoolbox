#!/bin/bash
################################################################################
# Purpose:
#     Find the largest file on specified mount. To be used by automation tools.
# Usage:
#     Run script with --help option to get usage.
################################################################################

version="1.0.0"

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

shopt -s expand_aliases
alias die='error_exit "ERROR in $0: line $LINENO:"'

# Usage.
usage() {
    echo "Usage:"
    echo "    $script_name [mount]"
    echo "Example:"
    echo "    $script_name /"
    exit 1
}

error_exit() {
    echo "$@" >&2
    exit 77
}

set -E
set -o pipefail
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

# Process options.
if [[ $1 == '--help' ]]; then
    usage
fi

path="$1"
if [[ $path = "" ]]; then
    path="/"
fi

set -o pipefail

while :; do
cd "$path" || die "Could not change directory."
echo "path: $path"
# Not displaying size initially because it is not reliably shown for / mount.
if [[ ! -z $size ]]; then
    echo "size: $size"
fi
dirfile="$(du -xs * 2> /dev/null | sort -n | tail -1 | awk '{print $2}')"
if [[ ! -d $path/$dirfile ]]; then
    break
fi
if [[ $path = "/" ]]; then
    path="/$dirfile"
else
    path="$path/$dirfile"
fi
echo
size="$(du -s --bytes $path | awk '{print $1}')"
done

echo
echo "file: $path/$dirfile"
du -s --bytes "$path/$dirfile" | awk '{print "size: " $1}'
