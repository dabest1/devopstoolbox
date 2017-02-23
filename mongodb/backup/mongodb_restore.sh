#!/bin/bash
################################################################################
# Purpose:
#     Restore MongoDB database.
################################################################################

version="1.0.10"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

# Variables.
s3_download_script="$script_dir/s3_download.sh"
restore_dir="/backups/restore"
mongorestore="$(which mongorestore)"
mongod="$(which mongod)"

# Functions.

shopt -s expand_aliases
alias die='error_exit "ERROR in $0: line $LINENO:"'

# Usage.
usage() {
    echo "Usage:"
    echo "    $script_name start -b backup_to_restore -s s3_bucket_path -p s3_profile"
    echo "    or"
    echo "    $script_name status -b backup_to_restore -s s3_bucket_path -p s3_profile"
    echo
    echo "Example:"
    echo "    $script_name start -b 20170101T010101Z.daily -s s3://dba-backup/mongodb/myhost -p dba-backup"
    echo
    echo "Description:"
    echo "    start                      Start a restore job."
    echo "    status                     Return status of a restore job."
    echo "    -b, --backup_to_restore    Dated subdirecotry of a backup to restore."
    echo "    -s, --s3_bucket_path       AWS S3 bucket path of where the backup is located."
    echo "    -p, --s3_profile           AWS S3 profile to use."
    echo "    --version                  Display script version."
    echo "    --help                     Display this help."
    exit 1
}

# Download backup.
get_backup() {
    echo "Downloading backup."
    if [[ ! -d $restore_path ]]; then
        mkdir -p "$restore_path"
    fi
    "$s3_download_script" "$s3_profile" "$s3_bucket_path/$backup_to_restore" "$restore_path" > "$restore_path/s3_download.log" 2> "$restore_path/s3_download.err"
    echo "Done."
    echo
}

# Verify md5 check sum.
verify_md5() {
    local rc

    echo "Verifying md5 check sum."
    cd "$restore_path" || exit 1
    find . -type f | grep -v '[.]log$' | grep -v '[.]err$' | grep -v 'md5sum.txt' | grep -v 'md5sum.verify.txt' | sort | xargs md5sum > "$restore_path/md5sum.verify.txt"
    diff "$restore_path/md5sum.txt" "$restore_path/md5sum.verify.txt"
    rc=$?
    if [[ $rc -ne 0 ]]; then echo "Error: md5 check sum does not match."; exit 1; fi
    echo "Done."
    echo
}

# Uncompress backup.
uncompress() {
    echo "Uncompressing backup."
    find "$restore_path" -name "*.bson.gz" -exec gunzip '{}' \;
    echo "Done."
    echo
}

# Restore backup.
restore() {
    local rc

    echo "Restoring backup."
    if [[ -d $restore_path/backup ]]; then
        "$mongorestore" "$restore_path/backup" &> "$restore_path/mongorestore.log"
        rc=$?
    else
        "$mongorestore" "$restore_path" &> "$restore_path/mongorestore.log"
        rc=$?
    fi
    if [[ $rc -ne 0 ]]; then echo "Error: mongorestore failed."; exit 1; fi
    echo "Done."
    echo
}

# Verify UUID.
verify_uuid() {
    local uuid
    local uuid_from_restore

    echo "Verifying UUID."
    uuid="$(grep "uuid:" "$restore_path/backup.log" | awk '{print $2}')"
    echo "uuid: $uuid"
    uuid_from_restore="$(mongo --quiet dba --eval "JSON.stringify(db.backup_uuid.findOne({uuid:\"$uuid\"}));" | jq '.uuid' | tr -d '"')"
    if [[ $uuid != "$uuid_from_restore" ]]; then
        echo "Error: UUID could not be verified."
        exit 1
    fi
    echo "Done."
}

# Start restore job.
start() {
    local end_time

    echo "**************************************************"
    echo "* Restore MongoDB"
    echo "* Time started: $start_time"
    echo "**************************************************"
    echo
    echo "Hostname: $HOSTNAME"
    echo "MongoDB version: $("$mongod" --version | head -1)"
    echo

    mkdir "$restore_path" || exit 1

    # Create restore status and pid file.
    echo "$BASHPID" > "$restore_pid_file"
    echo "{\"start_time\":\"$start_time\",\"backup_to_restore\":\"$backup_to_restore\",\"status\":\"running\"}" > "$restore_status_file"

    get_backup
    verify_md5
    uncompress
    restore
    verify_uuid

    end_time="$(date -u +'%FT%TZ')"
    echo "**************************************************"
    echo "* Time finished: $end_time"
    echo "**************************************************"

    # Update restore status file.
    echo "{\"start_time\":\"$start_time\",\"end_time\":\"$end_time\",\"backup_to_restore\":\"$backup_to_restore\",\"status\":\"completed\"}" > "$restore_status_file"
}

# Get restore job status.
status() {
    local pid
    local rc
    local status

    if [[ -f $restore_pid_file ]] && [[ -f $restore_status_file ]]; then
        pid="$(cat "$restore_pid_file")"
        kill -0 "$pid" 2> /dev/null
        rc=$?
        if [[ $rc -eq 0 ]]; then
            # Show status.
            cat "$restore_status_file"
            exit 0
        else
            status="$(jq '.status' < "$restore_status_file" | tr -d '"')"
            if [[ $status = "completed" ]]; then
                # Show status.
                cat "$restore_status_file"
                exit 0
            else
                # Show status.
                echo "{\"backup_to_restore\":\"$backup_to_restore\",\"status\":\"failed\"}"
                exit 0
            fi
        fi
    else
        # Show status.
        echo "{\"backup_to_restore\":\"$backup_to_restore\",\"status\":\"unknown\"}"
    fi
}

error_exit() {
    echo "$@" >&2
    exit 77
}

set -E
set -o pipefail
set -o errtrace
trap 'rc=$? && [[ $rc -ne 77 ]] && error_exit "ERROR in $0: line $LINENO: exit code $rc." || exit 77' ERR
trap 'error_exit "ERROR in $0: Received signal SIGHUP."' SIGHUP
trap 'error_exit "ERROR in $0: Received signal SIGINT."' SIGINT
trap 'error_exit "ERROR in $0: Received signal SIGTERM."' SIGTERM

# Process options.
while [[ -n $1 ]]; do
    case "$1" in
    --version)
        echo "version: $version"
        exit
        ;;
    --backup_to_restore|-b)
        shift
        backup_to_restore="$1"
        shift
        ;;
    --s3_bucket_path|-s)
        shift
        s3_bucket_path="$1"
        shift
        ;;
    --s3_profile|-p)
        shift
        s3_profile="$1"
        shift
        ;;
    start)
        command="start"
        shift
        ;;
    status)
        command="status"
        shift
        ;;
    *|--help)
        usage
    esac
done

restore_path="$restore_dir/$backup_to_restore"
restore_pid_file="$restore_path/restore.pid"
restore_status_file="$restore_path/restore.status.json"

if [[ $command = start ]]; then
    start
elif [[ $command = status ]]; then
    status
else
    usage
fi
