#!/bin/bash
################################################################################
# Purpose:
#     Restore MongoDB database with the use of Rundeck.
# Usage:
#     Run script with --help option to get usage.
################################################################################

version="2.2.1"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

# Variables.
s3_download_script="$script_dir/s3_download.sh"
restore_dir="/backups/restore"
mongo="$(which mongo)"
mongorestore="$(which mongorestore)"
mongod="$(which mongod)"
log="$restore_dir/restore.log"
log_err="$restore_dir/restore.err"

# Functions.

shopt -s expand_aliases
alias die='error_exit "ERROR in $0: line $LINENO:"'

# Usage.
usage() {
    echo "Usage:"
    echo "    $script_name start -b backup_to_restore -s s3_bucket_path -p s3_profile [--no_verify_md5] [--no_verify_uuid]"
    echo "    or"
    echo "    $script_name status -r restore_path"
    echo
    echo "Example:"
    echo "    $script_name start -b 20170101T010101Z.daily -s s3://dba-backup/mongodb/myhost -p aws_restore"
    echo "    $script_name status -r /backups/restore/20170102T205021Z_myhost"
    echo
    echo "Description:"
    echo "    Restore MongoDB database:"
    echo "    Get backup."
    echo "    Verify md5 check sum - verifies that there was no data corruption during disk/network transfer."
    echo "    Uncompress backup."
    echo "    Restore backup."
    echo "    Verify UUID - verifies that restore has the UUID which was inserted during backup."
    echo
    echo "    Options:"
    echo "    start                      Start a restore job."
    echo "    status                     Return status of a restore job."
    echo "    -b, --backup_to_restore    Dated subdirecotry of a backup to restore."
    echo "    -s, --s3_bucket_path       AWS S3 bucket path of where the backup is located."
    echo "    -p, --s3_profile           AWS S3 profile to use."
    echo "    -r, --restore_path         Restore path of existing restore job."
    echo "    --no_verify_md5            Disable MD5 check sum verification."
    echo "    --no_verify_uuid           Disable UUID verification."
    echo "    --version                  Display script version."
    echo "    --help                     Display this help."
    exit 1
}

# Download backup.
get_backup() {
    local rc

    echo "Downloading backup."
    if [[ ! -d $restore_path ]]; then
        mkdir -p "$restore_path"
    fi
    "$s3_download_script" "$s3_profile" "$s3_bucket_path/$backup_to_restore" "$restore_path" > "$restore_path/s3_download.log" 2> "$restore_path/s3_download.err"
    rc=$?
    if [[ $rc -ne 0 ]]; then die "S3 download failed."; fi
    echo "Done."
    echo
}

# Verify md5 check sum.
verify_md5() {
    local rc

    echo "Verifying md5 check sum."
    cd "$restore_path" || die "Could not change directory."
    find . -type f | grep -v '[.]/.*[.]log$' | grep -v '[.]/.*[.]err$' | grep -v '[.]/md5sum.txt' | grep -v '[.]/md5sum.verify.txt' | grep -v '[.]/restore.pid' | grep -v '[.]/restore.status.json' | sort | xargs md5sum > "$restore_path/md5sum.verify.txt"
    diff "$restore_path/md5sum.txt" "$restore_path/md5sum.verify.txt"
    rc=$?
    if [[ $rc -ne 0 ]]; then die "Md5 check sum does not match."; fi
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
    "$mongorestore" "$restore_path/backup" &> "$restore_path/mongorestore.log"
    rc=$?
    if [[ $rc -ne 0 ]]; then die "mongorestore failed."; fi
    if grep -q 'skipping...' "$restore_path/mongorestore.log"; then die "mongorestore skipped some files."; fi
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
    if [[ $uuid != "$uuid_from_restore" ]]; then die "UUID could not be verified."; fi
    echo "Done."
    echo
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
    echo "backup_to_restore: $backup_to_restore"
    echo "s3_bucket_path: $s3_bucket_path"
    echo "s3_profile: $s3_profile"
    echo

    if [[ ! -d $restore_dir ]]; then
        mkdir "$restore_dir"
    fi
    mkdir "$restore_path"

    # Move logs.
    mv "$log" "$restore_path/"
    mv "$log_err" "$restore_path/"
    log="$restore_path/$(basename "$log")"
    log_err="$restore_path/$(basename "$log_err")"

    # Create restore status and pid file.
    echo "$BASHPID" > "$restore_pid_file"
    echo "{\"start_time\":\"$start_time\",\"node_name\":\"$node_name\",\"backup_start_time\":\"$backup_start_time\",\"restore_path\":\"$restore_path\",\"status\":\"running\"}" > "$restore_status_file"

    get_backup
    if [[ $verify_md5_yn = yes ]]; then verify_md5; fi
    uncompress
    drop_dbs
    restore
    if [[ $verify_uuid_yn = yes ]]; then verify_uuid; fi

    end_time="$(date -u +'%FT%TZ')"
    echo "**************************************************"
    echo "* Time finished: $end_time"
    echo "**************************************************"

    # Update restore status file.
    echo "{\"start_time\":\"$start_time\",\"end_time\":\"$end_time\",\"node_name\":\"$node_name\",\"backup_start_time\":\"$backup_start_time\",\"restore_path\":\"$restore_path\",\"status\":\"completed\"}" > "$restore_status_file"
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
                echo "{\"restore_path\":\"$restore_path\",\"status\":\"failed\"}"
                exit 0
            fi
        fi
    else
        # Show status.
        echo "{\"restore_path\":\"$restore_path\",\"status\":\"unknown\"}"
    fi
}

# Drop current databases if any.
drop_dbs() {
    echo "Dropping databases:"
    "$mongo" --quiet --eval 'db.adminCommand( { listDatabases: 1 } ).databases.forEach(printjson);'
    "$mongo" --quiet --eval '
        var dbNames = db.getMongo().getDBNames();
        dbNames.forEach( function (name) { db = db.getSiblingDB(name); db.runCommand( { dropDatabase: 1 } ); } );
    '
    echo "Done."
    echo
}

error_exit() {
    echo "$@" >&2
    exit 77
}

set -o pipefail
#set -o errtrace
trap 'rc=$? && [[ $rc -ne 77 ]] && error_exit "ERROR in $0: line $LINENO: exit code $rc." || exit 77' ERR
trap 'error_exit "ERROR in $0: Received signal SIGHUP."' SIGHUP
trap 'error_exit "ERROR in $0: Received signal SIGINT."' SIGINT
trap 'error_exit "ERROR in $0: Received signal SIGTERM."' SIGTERM

# Process options.
verify_md5_yn="yes"
verify_uuid_yn="yes"
while [[ -n $1 ]]; do
    case "$1" in
    start)
        command="start"
        shift
        ;;
    status)
        command="status"
        shift
        ;;
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
    --restore_path|-r)
        shift
        restore_path="$1"
        shift
        ;;
    --no_verify_md5)
        verify_md5_yn="no"
        shift
        ;;
    --no_verify_uuid)
        verify_uuid_yn="no"
        shift
        ;;
    *|--help)
        if [[ $1 != '--help' ]]; then
            echo "Invalid option provided: $1"
        fi
        usage
    esac
done

if [[ $command = start ]]; then
    # Start restore in daemon mode.

    start_time_wot="$(tr 'T' ' ' <<<"$start_time")"
    node_name="$(basename "$s3_bucket_path")"
    restore_date="$(date -d "$start_time_wot" +'%Y%m%dT%H%M%SZ')"
    restore_path="$restore_dir/${restore_date}_$node_name"
    restore_pid_file="$restore_path/restore.pid"
    restore_status_file="$restore_path/restore.status.json"
    backup_start_time="${backup_to_restore:0:4}-${backup_to_restore:4:2}-${backup_to_restore:6:5}:${backup_to_restore:11:2}:${backup_to_restore:13:3}"

    # Output status in JSON.
    echo "{\"start_time\":\"$start_time\",\"node_name\":\"$node_name\",\"backup_start_time\":\"$backup_start_time\",\"restore_path\":\"$restore_path\",\"status\":\"running\"}"

    exec 1> "$log" 2> "$log" 2> "$log_err"
    start &
elif [[ $command = status ]]; then
    # Get restore status.

    restore_pid_file="$restore_path/restore.pid"
    restore_status_file="$restore_path/restore.status.json"

    status
else
    # Get usage.
    usage
fi
