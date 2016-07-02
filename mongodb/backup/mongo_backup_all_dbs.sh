#!/bin/bash
################################################################################
# Purpose:
#     Backup all MongoDB databases using mongodump (local db is excluded.).
#     --oplog option is used, so that backup will reflect a single moment in 
#     time.
#     Compress backup.
#     Send email upon completion.
#
#     To restore the backup:
#     find "backup_path" -name "*.bson.gz" -exec gunzip '{}' \;
#     mongorestore --oplogReplay --dir "backup_path"
################################################################################

# Version.
version="1.1.3"

start_time="$(date -u +'%F %T %Z')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

# Load configuration settings.
source "$config_path"

if [[ -z $bkup_dir ]]; then
    echo "Error: Some variables were not provided in configuration file." >&2
    exit 1
fi

# Redirect stderr into error log, stdout and stderr into log and terminal.
log="${log:-/tmp/backup.log}"
log_err="${log_err:-/tmp/backup.err}"
rm "$log" "$log_err" 2> /dev/null
exec 1> >(tee -ia "$log") 2> >(tee -ia "$log" >&2) 2> >(tee -ia "$log_err" >&2)

bkup_date="$(date -d "$start_time" +'%Y%m%dT%H%M%SZ')"
bkup_dow="$(date -d "$start_time" +'%w')"
if [[ -z "$user" ]]; then
    mongo_option=""
else
    mongo_option="-u $user -p $pass"
fi

echo "**************************************************"
echo "* Backup MongoDB Database"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "Hostname: $HOSTNAME"
echo "MongoDB version:"
mongod --version
echo

# Decide on what type of backup to perform.
if [[ -z "$bkup_type" ]]; then
    # Check if daily or weekly backup should be run.
    if [[ $bkup_dow -eq $weekly_bkup_dow ]]; then
        # Check if it is time to run monthly or yearly backup.
        bkup_y="$(date -d "$start_time" +'%Y')"
        yearly_bkup_exists="$(find "$bkup_dir" -name "*.yearly" | awk -F'/' '{print $NF}' | grep "^$bkup_y")"
        bkup_ym="$(date -d "$start_time" +'%Y%m')"
        monthly_bkup_exists="$(find "$bkup_dir" -name "*.monthly" | awk -F'/' '{print $NF}' | grep "^$bkup_ym")"
        bkup_yw="$(date -d "$start_time" +'%Y%U')"
        weekly_bkup_exists="$(find "$bkup_dir" -name "*.weekly" | awk -F'/' '{print $NF}' | awk -FT '{print $1}' | xargs -i date -d "{}" +'%Y%U' | grep "^$bkup_yw")"
        if [[ -z "$yearly_bkup_exists" && $num_yearly_bkups -ne 0 ]]; then
            bkup_type="yearly"
            num_bkups=$num_yearly_bkups
        elif [[ -z "$monthly_bkup_exists" && $num_monthly_bkups -ne 0 ]]; then
            bkup_type="monthly"
            num_bkups=$num_monthly_bkups
        elif [[ -z "$weekly_bkup_exists" && $num_weekly_bkups -ne 0 ]]; then
            bkup_type="weekly"
            num_bkups=$num_weekly_bkups
        else
            bkup_type="daily"
            num_bkups=$num_daily_bkups
        fi
    else
        bkup_type="daily"
        num_bkups=$num_daily_bkups
    fi
fi
echo "Backup type: $bkup_type"
echo "Number of backups to retain for this type: $num_bkups"
echo

echo "Backup will be created in:"
echo "$bkup_dir/$bkup_date.$bkup_type"
echo
mkdir "$bkup_dir/$bkup_date.$bkup_type"
# Move logs into dated backup directory.
mv "$log" "$bkup_dir/$bkup_date.$bkup_type/"
mv "$log_err" "$bkup_dir/$bkup_date.$bkup_type/"
log="$bkup_dir/$bkup_date.$bkup_type/$(basename "$log")"
log_err="$bkup_dir/$bkup_date.$bkup_type/$(basename "$log_err")"

# Purge old backups.
echo "Disk space before purge:"
df -h "$bkup_dir"
echo

echo "Purge old backups."
list_of_bkups="$(find "$bkup_dir" -name "*.$bkup_type" | sort)"
if [[ ! -z "$list_of_bkups" ]]; then
    while [[ "$(echo "$list_of_bkups" | wc -l)" -ge $num_bkups ]]; do
        old_bkup="$(echo "$list_of_bkups" | head -1)"
        echo "Deleting old backup: $old_bkup"
        rm -r "$old_bkup"
        list_of_bkups="$(find "$bkup_dir" -name "*.$bkup_type" | sort)"
    done
    echo
fi

# Perform backup.
echo "Disk space before backup:"
df -h "$bkup_dir"
echo

date -u +'start:  %F %T %Z'
if echo "$HOSTNAME" | grep -q 'cfgdb'; then
    # Config server
    echo "Backing up config server."
    "$mongodump" $mongo_option -o "$bkup_dir/$bkup_date.$bkup_type" --authenticationDatabase admin 2> "$bkup_dir/$bkup_date.$bkup_type/mongodump.log"
    rc=$?
else
    # Replica set member
    echo "Backing up all dbs except local with --oplog option."
    "$mongodump" $mongo_option -o "$bkup_dir/$bkup_date.$bkup_type" --authenticationDatabase admin --oplog 2> "$bkup_dir/$bkup_date.$bkup_type/mongodump.log"
    rc=$?
fi
if [[ $rc -ne 0 ]]; then
    cat "$bkup_dir/$bkup_date.$bkup_type/mongodump.log" >&2
fi
date -u +'finish: %F %T %Z'

echo
echo "Total disk usage:"
du -sb "$bkup_dir/$bkup_date.$bkup_type"
echo "Disk space after backup:"
df -h "$bkup_dir"
echo

# Compress backup.
echo "Compress backup."
date -u +'start:  %F %T %Z'
find "$bkup_dir/$bkup_date.$bkup_type" -name "*.bson" -exec gzip '{}' \;
date -u +'finish: %F %T %Z'
echo
echo "Total compressed disk usage:"
du -sb "$bkup_dir/$bkup_date.$bkup_type"
echo "Disk space after compression:"
df -h "$bkup_dir"
echo

if [[ ! -z $post_backup ]]; then
    cd "$script_dir"
    echo "Post backup process."
    echo "Command:"
    eval echo "$post_backup"
    date -u +'start:  %F %T %Z'
    eval "$post_backup"
    post_backup_rc=$?
    date -u +'finish: %F %T %Z'
    echo
fi

echo "**************************************************"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"

# Send email.
if [[ -s "$log_err" || $post_backup_rc -gt 0 ]]; then
    if [[ ! -z "$mail_on_error" ]]; then
        mail -s "Error - MongoDB Backup $HOSTNAME" "$mail_on_error" < "$log"
    fi
    exit 1
else
    if [[ ! -z "$mail_on_success" ]]; then
        mail -s "Success - MongoDB Backup $HOSTNAME" "$mail_on_success" < "$log"
    fi
    exit 0
fi
