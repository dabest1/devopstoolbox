#!/bin/bash
################################################################################
# Purpose:
#	Backup specific MongoDB database(s) using mongodump. --oplog option is 
#	not supported with this method, so backup may not reflect a single 
#	moment in time.
#	Compress backup.
#	Email upon completion.
#
#	To restore the backup:
#	find "backup_path" -name "*.bson.gz" -exec gunzip '{}' \;
#	mongorestore --dir "backup_path"
#
# Source:
#	https://github.com/dabest1/mongodb/blob/master/backup/mongo_backup_each_db.sh
################################################################################

# Version.
version="1.0.1"

# Main backup directory.
bkup_dir="/backups"
# Backup type such as adhoc, daily, weekly, monthly, or yearly. Optionally supply this value to override the calculated value.
bkup_type=""
# Day of week to produce weekly, monthly, or yearly backups.
weekly_bkup_dow=2
# Number of daily backups to retain.
num_daily_bkups=5
# Number of weekly backups to retain.
num_weekly_bkups=5
# Number of monthly backups to retain.
num_monthly_bkups=2
# Number of yearly backups to retain.
num_yearly_bkups=0
# MongoDB username.
user=""
# MongoDB password.
pass=""
# Where to email when errors occur. Leave empty if no email is desired.
mail_on_error=""
# Where to email when no errors occur. Leave empty if no email is desired.
mail_on_success=""
# Location of mongo binary.
mongo="/usr/bin/mongo"
# Location of mongodump binary.
mongodump="/usr/bin/mongodump"

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

# Get a list of databases to backup.
bkup_dbs="$("$mongo" $mongo_option admin --eval "rs.slaveOk(); printjson(db.adminCommand('listDatabases'))" | grep name | cut -d: -f2 | awk -F'"' '{print $2}')"
# Exclude 'local' database from backup.
bkup_dbs="$(echo "$bkup_dbs" | grep -v '^local$')"
echo "List of databases to backup:"
echo "$bkup_dbs"
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
mkdir "$bkup_dir/$bkup_date.$bkup_type"
for db in $bkup_dbs; do
	echo "Backing up db: $db"
	date -u +'start:  %F %T %Z'
	"$mongodump" $mongo_option -d "$db" -o "$bkup_dir/$bkup_date.$bkup_type" --authenticationDatabase admin 2> "$bkup_dir/$bkup_date.$bkup_type/mongodump.$db.log"
	rc=$?
	if [[ $rc -ne 0 ]]; then
		cat "$bkup_dir/$bkup_date.$bkup_type/mongodump.$db.log" >&2
	fi
	date -u +'finish: %F %T %Z'
	echo "Disk usage:"
	du -sb "$bkup_dir/$bkup_date.$bkup_type/$db"
	echo
done
echo "Total disk usage:"
du -sb "$bkup_dir/$bkup_date.$bkup_type"
echo

# Compress backup.
for db in $bkup_dbs; do
	echo "Compress db: $db"
	date -u +'start:  %F %T %Z'
	find "$bkup_dir/$bkup_date.$bkup_type/$db" -name "*.bson" -exec gzip '{}' \;
	date -u +'finish: %F %T %Z'
	echo "Disk usage:"
	du -sb "$bkup_dir/$bkup_date.$bkup_type/$db"
	echo
done

echo "Total compressed disk usage:"
du -sb "$bkup_dir/$bkup_date.$bkup_type"
echo

echo "**************************************************"
echo "* Backup MongoDB Database"
echo "* Time finished: $(date -u +'%F %T %Z')"
echo "**************************************************"

# Send email.
if [[ -s "$log_err" ]]; then
	if [[ ! -z "$mail_on_error" ]]; then
        	cat "$log_mail" | mail -s "Error - MongoDB Backup $HOSTNAME" "$mail_on_error"
	fi
	mv "$log_mail" "$bkup_dir/$bkup_date.$bkup_type/"
	mv "$log_err" "$bkup_dir/$bkup_date.$bkup_type/"
	exit 1
else
	if [[ ! -z "$mail_on_success" ]]; then
        	cat "$log_mail" | mail -s "Success - MongoDB Backup $HOSTNAME" "$mail_on_success"
	fi
	mv "$log_mail" "$bkup_dir/$bkup_date.$bkup_type/"
	mv "$log_err" "$bkup_dir/$bkup_date.$bkup_type/"
	exit 0
fi
