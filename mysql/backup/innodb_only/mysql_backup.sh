#!/bin/bash
################################################################################
# Purpose:
#     Backup MySQL database.
#     Compress backup.
#     Optionally run post backup script.
#     Optionally send email upon completion.
################################################################################

version="1.0.1"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

# Load configuration settings.
source "$config_path"

# Process options.
while test -n "$1"; do
    case "$1" in
    --version)
        echo "version: $version"
        exit
        ;;
    *)
        echo "Invalid parameter." >&2
        exit 1
    esac
done

# Variables.

if [[ -z $bkup_dir ]]; then
    echo "Error: Not all equired variables were provided in configuration file." >&2
    exit 1
fi
bkup_date="$(date -d "$start_time" +'%Y%m%dT%H%M%SZ')"
bkup_dow="$(date -d "$start_time" +'%w')"
weekly_bkup_dow="${weekly_bkup_dow:-1}"
num_daily_bkups="${num_daily_bkups:-5}"
num_weekly_bkups="${num_weekly_bkups:-5}"
num_monthly_bkups="${num_monthly_bkups:-2}"
num_yearly_bkups="${num_yearly_bkups:-0}"
if [[ -z "$user" ]]; then
    mysql_option=""
else
    mysql_option="--username=$user --password=$pass"
fi
log="$bkup_dir/backup.log"
log_err="$bkup_dir/backup.err"
mysql="${mysql:-$(which mysql)}"
mysqld="${mysqld:-$(which mysqld)}"
xtrabackup="${xtrabackup:-$(which xtrabackup)}"
xtrabackup_parallel="${xtrabackup_parallel:-1}"

# Functions.

error_exit() {
    echo
    echo "$@" >&2
    if [[ ! -z $mail_on_error ]]; then
        mail -s "Error - MySQL Backup $HOSTNAME" "$mail_on_error" < "$log"
    fi
    exit 77
}

main() {
    echo "**************************************************"
    echo "* Backup MySQL"
    echo "* Time started: $start_time"
    echo "**************************************************"
    echo
    echo "Hostname: $HOSTNAME"
    echo "mysqld version: $("$mysqld" --version 2> /dev/null)"
    echo "Backup type: $bkup_type"
    echo "Number of backups to retain for this type: $num_bkups"
    echo "Backup will be created in: $bkup_path"
    echo
    mkdir "$bkup_path" || error_exit "ERROR: ${0}(@$LINENO): Could not create directory."
    # Move logs into dated backup directory.
    mv "$log" "$bkup_path/"
    mv "$log_err" "$bkup_path/"
    log="$bkup_path/$(basename "$log")"
    log_err="$bkup_path/$(basename "$log_err")"

    purge_old_backups

    perform_backup

    post_backup_process

    echo "**************************************************"
    echo "* Time finished: $(date -u +'%FT%TZ')"
    echo "**************************************************"

    # Send email.
    if [[ -s "$log_err" ]]; then
        if [[ ! -z "$mail_on_error" ]]; then
            mail -s "Error - MySQL Backup $HOSTNAME" "$mail_on_error" < "$log"
        fi
        error_exit "ERROR: ${0}(@$LINENO): Unknown error."
    else
        if [[ ! -z "$mail_on_success" ]]; then
            mail -s "Success - MySQL Backup $HOSTNAME" "$mail_on_success" < "$log"
        fi
    fi
}

# Perform backup.
perform_backup() {
    echo "Disk space before backup:"
    df -h "$bkup_dir/"
    echo

    #if [[ $uuid_insert == yes ]]; then
        #echo "Insert UUID into database for restore validation."
        #uuid=$(uuidgen)
        #echo "uuid: $uuid"
        #echo
    #fi

    echo "Backing up database."
    date -u +'start: %FT%TZ'
    # --parallel=4
    # --compress-threads=4
    "$xtrabackup" --backup --target-dir="$bkup_path" --slave-info --skip-secure-auth $mysql_option --compress 2> "$bkup_path/xtrabackup.log"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        error_exit "ERROR: ${0}(@$LINENO): Backup failed."
    fi
    date -u +'finish: %FT%TZ'
    echo

    #if [[ $uuid_insert == yes ]]; then
        #echo "Remove UUID."
        #echo
    #fi

    echo "Backup size in bytes:"
    du -sb "$bkup_path"
    echo "Disk space after backup:"
    df -h "$bkup_dir/"
    echo
}

# Post backup process.
post_backup_process() {
    if [[ ! -z $post_backup ]]; then
        cd "$script_dir"
        echo "Post backup process."
        date -u +'start: %FT%TZ'
        echo "Command:"
        eval echo "$post_backup"
        eval "$post_backup"
        local rc=$?
        if [[ $rc -gt 0 ]]; then
            error_exit "ERROR: ${0}(@$LINENO): Post backup process failed."
        fi
        date -u +'finish: %FT%TZ'
        echo
    fi
}

# Purge old backups.
purge_old_backups() {
    echo "Disk space before purge:"
    df -h "$bkup_dir/"
    echo

    echo "Purge old backups..."
    local list_of_bkups="$(find "$bkup_dir/" -name "*.$bkup_type" | sort)"
    if [[ ! -z "$list_of_bkups" ]]; then
        while [[ "$(echo "$list_of_bkups" | wc -l)" -gt $num_bkups ]]; do
            old_bkup="$(echo "$list_of_bkups" | head -1)"
            echo "Deleting old backup: $old_bkup"
            rm -r "$old_bkup"
            list_of_bkups="$(find "$bkup_dir/" -name "*.$bkup_type" | sort)"
        done
    fi
    echo "Done."
    echo
}

# Decide on what type of backup to perform.
select_backup_type() {
    if [[ -z "$bkup_type" ]]; then
        # Check if daily or weekly backup should be run.
        if [[ $bkup_dow -eq $weekly_bkup_dow ]]; then
            # Check if it is time to run monthly or yearly backup.
            bkup_y="$(date -d "$start_time" +'%Y')"
            yearly_bkup_exists="$(find "$bkup_dir/" -name "*.yearly" | awk -F'/' '{print $NF}' | grep "^$bkup_y")"
            bkup_ym="$(date -d "$start_time" +'%Y%m')"
            monthly_bkup_exists="$(find "$bkup_dir/" -name "*.monthly" | awk -F'/' '{print $NF}' | grep "^$bkup_ym")"
            bkup_yw="$(date -d "$start_time" +'%Y%U')"
            weekly_bkup_exists="$(find "$bkup_dir/" -name "*.weekly" | awk -F'/' '{print $NF}' | awk -FT '{print $1}' | xargs -i date -d "{}" +'%Y%U' | grep "^$bkup_yw")"
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
}

set -E
set -o pipefail
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

# Redirect stderr into error log, stdout and stderr into log and terminal.
exec 1> >(tee -ia "$log") 2> >(tee -ia "$log" >&2) 2> >(tee -ia "$log_err" >&2)
select_backup_type
bkup_path="$bkup_dir/$bkup_date.$bkup_type"
main
