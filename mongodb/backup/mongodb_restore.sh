#!/bin/bash
################################################################################
# Purpose:
#     Restore MongoDB database.
################################################################################

version="1.0.3"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

# Variables.
s3_download_script="$script_dir/s3_download.sh"
restore_dir="/backups/restore"
mongorestore="/usr/bin/mongorestore"

# Process options.
while [[ -n $1 ]]; do
    case "$1" in
    --version)
        echo "version: $version"
        exit
        ;;
    --backup_to_restore|-b)
        backup_to_restore="$1"
        shift
        ;;
    --s3_bucket_path|-s)
        s3_bucket_path="$1"
        shift
        ;;
    --s3_profile|-p)
        s3_profile="$1"
        shift
        ;;
    *|--help)
        usage
    esac
done

# Functions.

# Usage.
usage() {
    echo "Usage:"
    echo "    $script_name -b backup_to_restore -s s3_bucket_path -p s3_profile"
    echo
    echo "Example:"
    echo "    $script_name -b 20170101T010101Z.daily -s s3://dba-backup/mongodb/myhost -p dba-backup"
    echo
    echo "Description:"
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
    echo "Verifying md5 check sum."
    cd "$restore_path" || exit 1
    find . -type f | grep -v '[.]log$' | grep -v '[.]err$' | grep -v 'md5sum.txt' | grep -v 'md5sum.verify.txt' | sort | xargs md5sum > "$restore_path/md5sum.verify.txt"
    diff "$restore_path/md5sum.txt" "$restore_path/md5sum.verify.txt"
    rc="$?"
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
    echo "Restoring backup."
    if [[ -d $restore_path/backup ]]; then
        "$mongorestore" "$restore_path/backup" &> "$restore_path/mongorestore.log"
        rc="$?"
    elif [[ -d $restore_path/data ]]; then
        "$mongorestore" "$restore_path/data" &> "$restore_path/mongorestore.log"
        rc="$?"
    else
        "$mongorestore" "$restore_path" &> "$restore_path/mongorestore.log"
        rc="$?"
    fi
    if [[ $rc -ne 0 ]]; then echo "Error: mongorestore failed."; exit 1; fi
    echo "Done."
    echo
}

# Verify UUID.
verify_uuid() {
    echo "Verifying UUID."
    uuid="$(grep "uuid:" "$restore_path/backup.log" | awk '{print $2}')"
    echo "uuid: $uuid"
    uuid_from_mongo="$(mongo --quiet dba --eval "JSON.stringify(db.backup_uuid.findOne({uuid:\"$uuid\"}));" | jq '.uuid' | tr -d '"')"
    if [[ $uuid != "$uuid_from_mongo" ]]; then
        echo "Error: UUID could not be verified."
        exit 1
    fi
    echo "Done."
}

echo "**************************************************"
echo "* Restore MongoDB"
echo "* Time started: $start_time"
echo "**************************************************"

restore_path="$restore_dir/$backup_to_restore"

get_backup
verify_md5
uncompress
restore
verify_uuid

end_time="$(date -u +'%FT%TZ')"
echo "**************************************************"
echo "* Time finished: $end_time"
echo "**************************************************"
