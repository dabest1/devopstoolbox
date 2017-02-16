#!/bin/bash
################################################################################
# Purpose:
#     Restore MongoDB database.
################################################################################

version="1.0.0"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

# Variables.

backup_to_restore="20170101T010101Z.daily"
s3_bucket_path="s3://dba-backup/mongodb/myhost"
s3_profile="dba-backup"
s3_download_script="$script_dir/s3_download.sh"
restore_dir="/backups/restore"
restore_path="$restore_dir/$backup_to_restore"
mongorestore="/usr/bin/mongorestore"

# Functions.

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
    "$mongorestore" "$restore_path/data" &> "$restore_path/mongorestore.log"
    rc="$?"
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
    if [[ $uuid != $uuid_from_mongo ]]; then
        echo "Error: UUID could not be verified."
        exit 1
    fi
    echo "Done."
}

get_backup
verify_md5
uncompress
restore
verify_uuid
