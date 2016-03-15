#!/bin/bash
################################################################################
# Purpose:
#	Backup all MongoDB databases using mongodump (local db is excluded.).
#	--oplog option is used, so that backup will reflect a single moment in 
#	time.
#	Compress backup.
#	Send email upon completion.
#
#	To restore the backup:
#	find "backup_path" -name "*.bson.gz" -exec gunzip '{}' \;
#	mongorestore --oplogReplay --dir "backup_path"
#
# Source:
#	https://github.com/dabest1/mongodb/blob/master/backup/mongo_backup_all_dbs.sh
################################################################################

# Version.
version="1.1.0"

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
log_err="$bkup_dir/error.log"
log_mail="$bkup_dir/mail.log"
rm "$log_err" "$log_mail" 2> /dev/null
exec 1> >(tee -ia "$log_mail") 2> >(tee -ia "$log_mail" >&2) 2> >(tee -ia "$log_err" >&2)

start_time="$(date -u +'%F %T %Z')"
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
		if [[ -z "$yearly_bkup_exists" && $num_yearly_bkups -ne 0 ]]; then
			bkup_type="yearly"
			num_bkups=$num_yearly_bkups
		elif [[ -z "$monthly_bkup_exists" && $num_monthly_bkups -ne 0 ]]; then
			bkup_type="monthly"
			num_bkups=$num_monthly_bkups
		elif [[ $num_weekly_bkups -ne 0 ]]; then
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

# Purge old backups.
list_of_bkups="$(find "$bkup_dir" -name "*.$bkup_type" | sort)"
if [[ ! -z "$list_of_bkups" ]]; then
	while [[ "$(echo "$list_of_bkups" | wc -l)" -ge $num_bkups ]]
	do
		old_bkup="$(echo "$list_of_bkups" | head -1)"
		echo "Deleting old backup: $old_bkup"
		rm -r "$old_bkup"
		list_of_bkups="$(find "$bkup_dir" -name "*.$bkup_type" | sort)"
	done
	echo
fi

# Perform backup.
echo "Backup will be created in:"
echo "$bkup_dir/$bkup_date.$bkup_type"
echo
echo "Disk space before backup:"
df -h "$bkup_dir"
echo
mkdir "$bkup_dir/$bkup_date.$bkup_type"
echo "Backing up all dbs except local with --oplog option."
date -u +'start:  %F %T %Z'
"$mongodump" $mongo_option -o "$bkup_dir/$bkup_date.$bkup_type" --authenticationDatabase admin --oplog 2> "$bkup_dir/$bkup_date.$bkup_type/mongodump.log"
rc=$?
if [[ $rc -ne 0 ]]; then
	cat "$bkup_dir/$bkup_date.$bkup_type/mongodump.log" >&2
fi
date -u +'finish: %F %T %Z'
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
echo "Total compressed disk usage:"
du -sb "$bkup_dir/$bkup_date.$bkup_type"
echo "Disk space after compression:"
df -h "$bkup_dir"
echo

echo "**************************************************"
echo "* Backup MongoDB Database"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"

# Send email.
if [[ -s "$log_err" ]]; then
	if [[ ! -z "$mail_on_error" ]]; then
        	mail -s "Error - MongoDB Backup $HOSTNAME" "$mail_on_error" < "$log_mail"
	fi
	mv "$log_mail" "$bkup_dir/$bkup_date.$bkup_type/"
	mv "$log_err" "$bkup_dir/$bkup_date.$bkup_type/"
	exit 1
else
	if [[ ! -z "$mail_on_success" ]]; then
        	mail -s "Success - MongoDB Backup $HOSTNAME" "$mail_on_success" < "$log_mail"
	fi
	mv "$log_mail" "$bkup_dir/$bkup_date.$bkup_type/"
	mv "$log_err" "$bkup_dir/$bkup_date.$bkup_type/"
	exit 0
fi
