#!/bin/bash
################################################################################
# Purpose:
#     MongoDB cluster backup with the use of Rundeck.
#     Backup all MongoDB databases using mongodump (local db is excluded).
#     --oplog option is used.
#     Compress backup.
#     Optionally run post backup script.
#     Optionally send email upon completion.
#
#     To restore the backup:
#     find "backup_path/" -name "*.bson.gz" -exec gunzip '{}' \;
#     mongorestore --oplogReplay --dir "backup_path"
################################################################################

version="1.2.1"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

# Load configuration settings.
source "$config_path"

if [[ -z $bkup_dir ]]; then
    echo "Error: Some variables were not provided in configuration file." >&2
    exit 1
fi

declare -A replset_bkup_execution_id

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
port="${port:-27017}"

# Functions.
error_exit() {
    echo
    echo "$@" >&2
    if [[ ! -z "$mail_on_error" ]]; then
        mail -s "Error - MongoDB Backup $HOSTNAME" "$mail_on_error" < "$log"
    fi
    exit 1
}
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

start_balancer() {
    echo "Start the balancer."
    "$mongo" --quiet "$mongos_host_port" --eval "sh.startBalancer()"
    balancer_state="$("$mongo" --quiet "$mongos_host_port" --eval "sh.getBalancerState()")"
    echo "Balancer state: $balancer_state"
}

shopt -s expand_aliases
alias die='error_exit "ERROR: ${0}(@$LINENO):"'

# Main.
echo "**************************************************"
echo "* Backup MongoDB Sharded Cluster"
echo "* Time started: $start_time"
echo "**************************************************"
echo
echo "Hostname: $HOSTNAME"
echo "MongoDB version: $("$mongod" --version | head -1)"
echo

# Decide on what type of backup to perform.
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
echo "Backup type: $bkup_type"
echo "Number of backups to retain for this type: $num_bkups"
echo

echo "Backup will be created in: $bkup_dir/$bkup_date.$bkup_type"
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

echo "Purge old backups..."
list_of_bkups="$(find "$bkup_dir/" -name "*.$bkup_type" | sort)"
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

# Perform backup.
echo "Disk space before backup:"
df -h "$bkup_dir"
echo

if [[ $uuid_insert == yes ]]; then
    echo "Insert UUID into database for restore validation."
    uuid=$(uuidgen)
    echo "uuid: $uuid"
    "$mongo" --quiet --port "$port" $mongo_option --authenticationDatabase admin dba --eval "db.backup_uuid.insert( { uuid: \"$uuid\" } )"
    echo
fi

if echo "$HOSTNAME" | grep -q 'cfgdb'; then
    # Config server.
    echo "This is a config server."
    mongos_host_port="$(mongo localhost:27017/config --quiet --eval 'rs.slaveOk(); var timeOffset = new Date(); timeOffset.setTime(timeOffset.getTime() - 60*60*1000); var cursor = db.mongos.find({ping:{$gte:timeOffset}},{_id:1}).sort({ping:-1}); while(cursor.hasNext()) { print(JSON.stringify(cursor.next())) }' | awk -F'"' '{print $4}' | head -1)"
    if [[ -z $mongos_host_port ]]; then
        die "mongos was not found."
    fi

    result="$("$mongo" --quiet "$mongos_host_port" --eval "sh.getBalancerState()")"
    echo "Balancer state: $result"
    echo "Stop the balancer..."
    "$mongo" --quiet "$mongos_host_port" --eval "sh.stopBalancer()"
    result="$("$mongo" --quiet "$mongos_host_port" --eval "sh.getBalancerState()")"
    echo "Balancer state: $result"
    if [[ $result != "false" ]]; then
        echo "Balancer could not be stopped." >&2
        start_balancer
        die "Balancer could not be stopped."
    fi
    for (( i=1; i<=3600; i++ )); do
        result="$("$mongo" --quiet "$mongos_host_port" --eval "sh.isBalancerRunning()")"
        if [[ $result = "false" ]]; then
            break
        fi
        sleep 1
    done
    if [[ $result != "false" ]]; then
        echo "Balancer is still running." >&2
        start_balancer
        die "Balancer is still running."
    fi

    echo
    echo "Backing up config server."
    date -u +'start: %FT%TZ'
    echo "Note: Need to identify in which cases --oplog does not work on config server. MongoDB 2.6 supports it. https://docs.mongodb.com/v2.6/tutorial/backup-sharded-cluster-with-database-dumps/#backup-one-config-server"
    #"$mongodump" --port "$port" $mongo_option -o "$bkup_dir/$bkup_date.$bkup_type" --authenticationDatabase admin 2> "$bkup_dir/$bkup_date.$bkup_type/mongodump.log"
    "$mongodump" --port "$port" $mongo_option -o "$bkup_dir/$bkup_date.$bkup_type" --authenticationDatabase admin --oplog 2> "$bkup_dir/$bkup_date.$bkup_type/mongodump.log"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        cat "$bkup_dir/$bkup_date.$bkup_type/mongodump.log" >&2
        start_balancer
        die "Config server backup failed."
    fi
    date -u +'finish: %FT%TZ'

    # Get shard servers (replica set members).
    replset_hosts_ports="$("$mongo" --quiet config --eval 'var myCursor = db.shards.find(); myCursor.forEach(printjson)' | jq '.host' | tr -d '"' | awk -F'/' '{print $2}' | tr ',' '\n')"
    replset_hosts="$(echo "$replset_hosts_ports" | awk -F: '{print $1}')"
    replset_hosts_bkup="$(echo "$replset_hosts" | grep "$bkup_host_regex")"

    # Backup replica sets.
    for host in $replset_hosts_bkup; do
        echo
        echo "Initiating backup job on replica set $host via Rundeck."
        rundeck_job="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X POST "${rundeck_server_url}/api/17/job/${rundeck_job_id}/run?authtoken=${rundeck_api_token}&filter=${host}")"
        echo "$rundeck_job" | jq .
        rc=$?
        if [[ $rc != 0 ]]; then
            echo "$rundeck_job" >&2
            die "Rundeck API call failed."
        fi
        job_status="$(echo "$rundeck_job" | jq '.status' | tr -d '"')"
        if [[ $job_status != "running" ]]; then
            #echo "$rundeck_job" >&2
            start_balancer
            die "Rundeck job could not be executed."
        fi
        replset_bkup_execution_id["$host"]="$(echo "$rundeck_job" | jq '.id')"
    done

    # Wait for completion of Rundeck jobs for replica set backups.
    for host in $replset_hosts_bkup; do
        echo
        echo "host: $host"
        for (( i=1; i<=1440; i++ )); do
            #rundeck_execution_output="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X GET "${rundeck_server_url}/api/17/execution/${replset_bkup_execution_id[$host]}/output/node/${host}?authtoken=${rundeck_api_token}")"
            rundeck_execution_state="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X GET "${rundeck_server_url}/api/17/execution/${replset_bkup_execution_id[$host]}/state?authtoken=${rundeck_api_token}")"
            #echo "$rundeck_execution_state" | jq .
            rc=$?
            if [[ $rc != 0 ]]; then
                echo "$rundeck_execution_state" >&2
                die "Rundeck API call failed."
            fi
            execution_state="$(echo "$rundeck_execution_state" | jq '.executionState' | tr -d '"')"
            echo "execution_state: $execution_state"
            if [[ $execution_state = "RUNNING" ]]; then
                sleep 60
            elif [[ $execution_state = "SUCCEEDED" ]]; then
                break
            else
                die "Backup job on replica set failed."
            fi
        done
    done

    echo
    start_balancer
else
    # Replica set member.
    echo "Backing up all dbs except local with --oplog option."
    date -u +'TS: %FT%TZ'
    "$mongodump" --port "$port" $mongo_option -o "$bkup_dir/$bkup_date.$bkup_type" --authenticationDatabase admin --oplog 2> "$bkup_dir/$bkup_date.$bkup_type/mongodump.log"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        #cat "$bkup_dir/$bkup_date.$bkup_type/mongodump.log" >&2
        die "mongodump failed."
    fi
    date -u +'TS: %FT%TZ'
fi
echo

if [[ $uuid_insert == yes ]]; then
    echo "Remove UUID."
    "$mongo" --quiet --port "$port" $mongo_option --authenticationDatabase admin dba --eval "db.backup_uuid.remove( { uuid: \"$uuid\" } )"
    echo
fi

echo "Total disk usage:"
du -sb "$bkup_dir/$bkup_date.$bkup_type"
echo "Disk space after backup:"
df -h "$bkup_dir"
echo

# Compress backup.
echo "Compress backup."
date -u +'start: %FT%TZ'
find "$bkup_dir/$bkup_date.$bkup_type" -name "*.bson" -exec gzip '{}' \;
date -u +'finish: %FT%TZ'
echo
echo "Total compressed disk usage:"
du -sb "$bkup_dir/$bkup_date.$bkup_type"
echo "Disk space after compression:"
df -h "$bkup_dir"
echo

if [[ ! -z $post_backup ]]; then
    cd "$script_dir"
    echo "Post backup process."
    date -u +'start: %FT%TZ'
    echo "Command:"
    eval echo "$post_backup"
    eval "$post_backup"
    rc=$?
    if [[ $rc -gt 0 ]]; then
        die "Post backup process failed."
    fi
    date -u +'finish: %FT%TZ'
    echo
fi

echo "**************************************************"
echo "* Time finished: $(date -u +'%FT%TZ')"
echo "**************************************************"

# Send email.
if [[ -s "$log_err" ]]; then
    if [[ ! -z "$mail_on_error" ]]; then
        mail -s "Error - MongoDB Backup $HOSTNAME" "$mail_on_error" < "$log"
    fi
    die "Uknown error."
else
    if [[ ! -z "$mail_on_success" ]]; then
        mail -s "Success - MongoDB Backup $HOSTNAME" "$mail_on_success" < "$log"
    fi
fi
