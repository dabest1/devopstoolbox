#!/bin/bash
################################################################################
# Purpose:
#     MongoDB cluster backup with the use of Rundeck. Replica set backups are 
#     also supported.
#     Backup all MongoDB databases using mongodump (local db is excluded).
#     --oplog option is used.
#     Compress backup.
#     Optionally run post backup script.
#     Optionally send email upon completion.
#
#     To restore the backup:
#     find "backup_path/" -name "*.bson.gz" -exec gunzip '{}' \;
#     mongorestore --oplogReplay --dir "backup_path"
#
#     This script does not rely on Rundeck to wait for the job to complete. 
#     Instead it starts the backup jobs in daemon mode and then sends status 
#     calls via another Rundeck job to track progress of the backup jobs.
################################################################################

version="2.3.0"

start_time="$(date -u +'%FT%TZ')"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"
config_path="$script_dir/${script_name/.sh/.cfg}"

# Load configuration settings.
if [[ -f "$config_path" ]]; then
    source "$config_path"
fi

# Process options.
while test -n "$1"; do
    case "$1" in
    --version)
        echo "version: $version"
        exit
        ;;
    start)
        command="start"
        shift
        ;;
    status)
        command="status"
        shift
        bkup_path="$1"
        shift
        ;;
    *)
        shift
    esac
done

# Variables.

if [[ -z $bkup_dir || -z $rundeck_server_url || -z $rundeck_api_token || -z $rundeck_job_id ]]; then
    echo "Error: Not all required variables were provided in configuration file." >&2
    exit 1
fi
start_time_wot="$(tr 'T' ' ' <<<"$start_time")"
bkup_date="$(date -d "$start_time_wot" +'%Y%m%dT%H%M%SZ')"
bkup_dow="$(date -d "$start_time_wot" +'%w')"
weekly_bkup_dow="${weekly_bkup_dow:-1}"
num_daily_bkups="${num_daily_bkups:-5}"
num_weekly_bkups="${num_weekly_bkups:-5}"
num_monthly_bkups="${num_monthly_bkups:-2}"
num_yearly_bkups="${num_yearly_bkups:-0}"
port="${port:-27017}"
if [[ -z "$user" ]]; then
    mongo_option=""
else
    mongo_option="-u $user -p $pass"
fi
log="$bkup_dir/backup.log"
log_err="$bkup_dir/backup.err"
mongo="${mongo:-$(which mongo)}"
mongod="${mongod:-$(which mongod)}"
mongodump="${mongodump:-$(which mongodump)}"
bkup_host_port_regex="${bkup_host_port_regex:-.*-2:[0-9]*}"
config_server_regex="${config_server_regex:-cfgdb}"

rundeck_status_check_iterations=432
rundeck_sleep_seconds_between_status_checks=300
mongodb_is_balancer_running_iterations=720
mongodb_sleep_seconds_between_is_balancer_running=5
need_to_start_balancer="false"
terminal_width=80
declare -A replset_bkup_execution_id
declare -A replset_bkup_path
declare -A replset_end_time
declare -A replset_start_time

# Functions.

# Compress backup.
compress_backup() {
    echo "Compress backup."
    date -u +'start: %FT%TZ'
    find "$bkup_path" -name "*.bson" -exec gzip '{}' \;
    date -u +'finish: %FT%TZ'
    echo
    echo "Compressed backup size in bytes:"
    du -sb "$bkup_path"
    echo "Disk space after compression:"
    df -h "$bkup_dir/"
    echo
}

error_exit() {
    echo
    echo "$@" >&2
    start_balancer >&2
    if [[ ! -z $mail_on_error ]]; then
        mail -s "Error - MongoDB Backup $HOSTNAME" "$mail_on_error" < "$log"
    fi
    exit 77
}

main() {
    echo "**************************************************"
    echo "* Backup MongoDB"
    echo "* Time started: $start_time"
    echo "**************************************************"
    echo
    echo "Hostname: $HOSTNAME"
    echo "MongoDB version: $("$mongod" --version | head -1)"
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

    # Create backup status and pid file.
    echo "$BASHPID" > "$bkup_pid_file"
    cat <<HERE_DOC > "$bkup_status_file"
{"start_time":"$start_time","backup_path":"$bkup_path","status":"running"}
HERE_DOC

    purge_old_backups

    perform_backup

    compress_backup

    post_backup_process

    end_time="$(date -u +'%FT%TZ')"
    echo "**************************************************"
    echo "* Time finished: $end_time"
    echo "**************************************************"

    # Send email.
    if [[ -s "$log_err" ]]; then
        if [[ ! -z "$mail_on_error" ]]; then
            mail -s "Error - MongoDB Backup $HOSTNAME" "$mail_on_error" < "$log"
        fi
        error_exit "ERROR: ${0}(@$LINENO): Unknown error."
    else
        if [[ ! -z "$mail_on_success" ]]; then
            mail -s "Success - MongoDB Backup $HOSTNAME" "$mail_on_success" < "$log"
        fi
    fi

    # Update backup status file.
    if [[ -z $replset_hosts_ports_bkup ]]; then
        cat <<HERE_DOC > "$bkup_status_file"
{"start_time":"$start_time","end_time":"$end_time","backup_path":"$bkup_path","status":"completed"}
HERE_DOC
    else
        backup_nodes_json="\"backup_nodes\":["
        while IFS=':' read -r host port; do
            backup_nodes_json="${backup_nodes_json}{\"node\":\"$host:$port\",\"start_time\":\"${replset_start_time[$host]}\",\"end_time\":\"${replset_end_time[$host]}\",\"backup_path\":\"${replset_bkup_path[$host]}\"},"
        done <<<"$replset_hosts_ports_bkup"
        backup_nodes_json="$(sed 's/,$//' <<<"$backup_nodes_json")]"

        cat <<HERE_DOC > "$bkup_status_file"
{"start_time":"$start_time","end_time":"$end_time","backup_path":"$bkup_path","status":"completed",$backup_nodes_json}
HERE_DOC
    fi
}

# Perform backup.
perform_backup() {
    echo "Disk space before backup:"
    df -h "$bkup_dir/"
    echo

    # Config server.
    if echo "$HOSTNAME" | grep -q "$config_server_regex"; then
        echo "This is a config server."

        if [[ $uuid_insert == yes ]]; then
            echo "Insert UUID into database for restore validation."
            uuid=$(uuidgen)
            echo "uuid: $uuid"
            "$mongo" --quiet --port "$port" $mongo_option --authenticationDatabase admin dba --eval "db.backup_uuid.insert( { uuid: \"$uuid\" } )"
            echo
        fi

        mongos_host_port="$("$mongo" localhost:27017/config --quiet --eval 'rs.slaveOk(); var timeOffset = new Date(); timeOffset.setTime(timeOffset.getTime() - 60*60*1000); var cursor = db.mongos.find({ping:{$gte:timeOffset}},{_id:1}).sort({ping:-1}); while(cursor.hasNext()) { print(JSON.stringify(cursor.next())) }' | awk -F'"' '{print $4}' | head -1)"
        if [[ -z $mongos_host_port ]]; then
            error_exit "ERROR: ${0}(@$LINENO): mongos was not found."
        fi

        stop_balancer

        echo
        echo "Backing up config server."
        date -u +'start: %FT%TZ'
        if [[ -e /etc/mongod.conf ]]; then
            cp -p /etc/mongod.conf "$bkup_path/"
        fi
        if [[ -e /etc/mongos.conf ]]; then
            cp -p /etc/mongos.conf "$bkup_path/"
        fi
        "$mongodump" --port "$port" $mongo_option -o "$bkup_path/backup" --authenticationDatabase admin --oplog &> "$bkup_path/mongodump.log"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            # Check if dump failed because the config server is not running with --configsvr option.
            if grep -q 'No operations in oplog. Please ensure you are connecting to a master.' "$bkup_path/mongodump.log"; then
                "$mongodump" --port "$port" $mongo_option -o "$bkup_path/backup" --authenticationDatabase admin &> "$bkup_path/mongodump.log"
                rc=$?
            fi
        fi
        if [[ $rc -ne 0 ]]; then
            error_exit "ERROR: ${0}(@$LINENO): mongodump failed."
        fi

        if [[ $uuid_insert == yes ]]; then
            echo "Remove UUID."
            "$mongo" --quiet --port "$port" $mongo_option --authenticationDatabase admin dba --eval "db.backup_uuid.remove( { uuid: \"$uuid\" } )"
            echo
        fi

        date -u +'finish: %FT%TZ'

        # Get shard servers (replica set members).
        shard_hosts_ports="$("$mongo" --quiet config --eval 'var myCursor = db.shards.find(); myCursor.forEach(printjson)' | jq '.host' | tr -d '"' | awk -F'/' '{print $2}' | awk -F, '{print $1}')"
        for host_port in $shard_hosts_ports; do
            replset_hosts_ports="$("$mongo" "$host_port" --quiet --eval 'JSON.stringify(rs.conf())' | jq '.members[].host' | tr -d '"')"
            if [[ -z $replset_hosts_ports_bkup ]]; then
                replset_hosts_ports_bkup="$(sed 's/[.].*:/:/' <<<"$replset_hosts_ports" | egrep "$bkup_host_port_regex")"
            else
                replset_hosts_ports_bkup="$replset_hosts_ports_bkup"$'\n'"$(sed 's/[.].*:/:/' <<<"$replset_hosts_ports" | egrep "$bkup_host_port_regex")"
            fi
        done
        echo

        if [[ -z $replset_hosts_ports_bkup ]]; then
            error_exit "ERROR: ${0}(@$LINENO): Could not get nodes of a replica set."
        fi

        # Run Rundeck jobs to start replica set backups.
        while IFS=':' read -r host port; do
            echo "host: $host:$port"
            echo "Start backup job on replica set via Rundeck."
            replset_bkup_execution_id["$host"]="$(rundeck_run_job "$rundeck_job_id" "{\"argString\":\"-command start\"}")"
        done <<<"$replset_hosts_ports_bkup"
        echo

        # Wait for Rundeck jobs to complete.
        while IFS=':' read -r host port; do
            echo "host: $host:$port"
            execution_state="$(rundeck_wait_for_job_to_complete "${replset_bkup_execution_id[$host]}")"
            echo "execution_state: $execution_state"
        done <<<"$replset_hosts_ports_bkup"
        echo

        # Get output of Rundeck jobs.
        while IFS=':' read -r host port; do
            echo "host: $host:$port"
            execution_log="$(rundeck_get_execution_output_log "$rundeck_server_url" "$rundeck_api_token" "${replset_bkup_execution_id[$host]}" "$host")"
            replset_bkup_path["$host"]="$(jq '.backup_path' <<<"$execution_log" | tr -d '"')"
            rc=$?; if [[ $rc -ne 0 ]]; then error_exit "ERROR: ${0}(@$LINENO): Could not parse Rundeck results."; fi
            echo "replset_bkup_path: ${replset_bkup_path[$host]}"
            replset_start_time["$host"]="$(jq '.start_time' <<<"$execution_log" | tr -d '"')"
            rc=$?; if [[ $rc -ne 0 ]]; then error_exit "ERROR: ${0}(@$LINENO): Could not parse Rundeck results."; fi
        done <<<"$replset_hosts_ports_bkup"

        # Run Rundeck jobs to get status of replica set backups.
        while IFS=':' read -r host port; do
            echo
            echo "Wait for replica set backup to complete."
            echo "Sleep for $rundeck_sleep_seconds_between_status_checks seconds between status checks."
            echo -n "host: $host:$port"
            for (( i=0; i<"$rundeck_status_check_iterations"; i++ )); do
                # Start get status from replica set via Rundeck.
                replset_bkup_execution_id["$host"]="$(rundeck_run_job_failok "$rundeck_server_url" "$rundeck_api_token" "$host" "$rundeck_job_id" "{\"argString\":\"-command status -backup-path ${replset_bkup_path[$host]}\"}")"
                rc=$?
                if [[ $rc -ne 0 ]]; then
                    sleep "$rundeck_sleep_seconds_between_status_checks"
                    if [[ $(( i % terminal_width )) -eq 0 ]]; then
                        echo
                    fi
                    echo -n "$rc"
                    continue
                fi

                # Wait for Rundeck job to complete.
                execution_state="$(rundeck_wait_for_job_to_complete "${replset_bkup_execution_id[$host]}")"

                # Get output of Rundeck job.
                execution_log="$(rundeck_get_execution_output_log "$rundeck_server_url" "$rundeck_api_token" "${replset_bkup_execution_id[$host]}" "$host")"
                status="$(jq '.status' <<<"$execution_log" | tr -d '"')"
                rc=$?; if [[ $rc -ne 0 ]]; then error_exit "ERROR: ${0}(@$LINENO): Could not parse Rundeck results."; fi

                if [[ $status = "completed" ]]; then
                    echo
                    echo "status: $status"
                    replset_end_time["$host"]="$(jq '.end_time' <<<"$execution_log" | tr -d '"')"
                    rc=$?; if [[ $rc -ne 0 ]]; then error_exit "ERROR: ${0}(@$LINENO): Could not parse Rundeck results."; fi
                    break
                elif [[ $status = "failed" ]]; then
                    echo
                    echo "status: $status"
                    error_exit "ERROR: ${0}(@$LINENO): Backup of replica set on $host failed."
                fi

                sleep "$rundeck_sleep_seconds_between_status_checks"
                if [[ $(( i % terminal_width )) -eq 0 ]]; then
                    echo
                fi
                echo -n "."
            done

            if [[ $status != "completed" ]]; then
                echo
                echo "status: $status"
                error_exit "ERROR: ${0}(@$LINENO): Backup of replica set on $host took too long."
            fi
        done <<<"$replset_hosts_ports_bkup"

        echo
        start_balancer
        echo

    # Replica set member.
    else
        is_master="$("$mongo" --quiet --port "$port" $mongo_option --authenticationDatabase admin --eval 'JSON.stringify(db.isMaster())' | jq '.ismaster')"
        if [[ $is_master != "false" ]]; then
            error_exit "ERROR: ${0}(@$LINENO): This is not a secondary node."
        fi

        if [[ $uuid_insert == yes ]]; then
            echo "Insert UUID into database for restore validation."
            uuid=$(uuidgen)
            echo "uuid: $uuid"
            primary_host_port="$("$mongo" --quiet --port "$port" $mongo_option --authenticationDatabase admin dba --eval 'JSON.stringify(rs.isMaster())' | jq '.primary' | tr -d '"')"
            "$mongo" --quiet --host "$primary_host_port" $mongo_option --authenticationDatabase admin dba --eval "db.backup_uuid.insert( { uuid: \"$uuid\" } )"
            echo

            # Verify that UUID showed up in this replica set.
            for (( i=1; i<=60; i++ )); do
                uuid_from_mongo="$("$mongo" --quiet --port "$port" $mongo_option --authenticationDatabase admin dba --eval "rs.slaveOk(); JSON.stringify(db.backup_uuid.findOne({uuid:\"$uuid\"}));" | jq '.uuid' | tr -d '"')"
                if [[ $uuid = "$uuid_from_mongo" ]]; then
                    contains_uuid="yes"
                    break
                fi
            done
            if [[ $contains_uuid != "yes" ]]; then
                error_exit "ERROR: ${0}(@$LINENO): Inserted UUID was not found on this MongoDB node."
            fi
        fi

        echo "Backing up all dbs except local with --oplog option."
        date -u +'start: %FT%TZ'
        if [[ -e /etc/mongod.conf ]]; then
            cp -p /etc/mongod.conf "$bkup_path/"
        fi
        "$mongodump" --port "$port" $mongo_option -o "$bkup_path/backup" --authenticationDatabase admin --oplog &> "$bkup_path/mongodump.log"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            error_exit "ERROR: ${0}(@$LINENO): mongodump failed."
        fi
        date -u +'finish: %FT%TZ'
        echo

        if [[ $uuid_insert == yes ]]; then
            echo "Remove UUID."
            "$mongo" --quiet --host "$primary_host_port" $mongo_option --authenticationDatabase admin dba --eval "db.backup_uuid.remove( { uuid: \"$uuid\" } )"
            echo
        fi
    fi

    echo "Backup size in bytes:"
    du -sb "$bkup_path"
    echo "Disk space after backup:"
    df -h "$bkup_dir/"
    echo
}

# Post backup process.
post_backup_process() {
    if [[ ! -z $post_backup ]]; then
        cd "$script_dir" || error_exit "ERROR: ${0}(@$LINENO): Cannot change directory."
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
    local list_of_bkups

    echo "Disk space before purge:"
    df -h "$bkup_dir/"
    echo

    echo "Purge old backups..."
    list_of_bkups="$(find "$bkup_dir/" -maxdepth 1 -type d -name "[0-9]*T[0-9]*Z.$bkup_type" | sort)"
    if [[ ! -z "$list_of_bkups" ]]; then
        while [[ "$(echo "$list_of_bkups" | wc -l)" -gt $num_bkups ]]; do
            old_bkup="$(echo "$list_of_bkups" | head -1)"
            echo "Deleting old backup: $old_bkup"
            rm -r "$old_bkup"
            list_of_bkups="$(find "$bkup_dir/" -maxdepth 1 -type d -name "[0-9]*T[0-9]*Z.$bkup_type" | sort)"
        done
    fi
    echo "Done."
    echo
}

# Get output from Rundeck execution, return just the log portion.
rundeck_get_execution_output_log() {
    local rundeck_server_url="$1"
    local rundeck_api_token="$2"
    local execution_id="$3"
    local node_name="$4"
    local rc
    local result
    local result_log

    result="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X GET "${rundeck_server_url}/api/17/execution/${execution_id}/output/node/${node_name}?authtoken=${rundeck_api_token}")"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "$result" >&2
        error_exit "ERROR: ${0}(@$LINENO): Rundeck API call failed."
    fi
    result_log="$(echo "$result" | jq '.entries[].log' | sed 's/^"//;s/"$//;s/\\"/"/g')"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "$result" >&2
        error_exit "ERROR: ${0}(@$LINENO): Could not parse Rundeck results."
    fi
    echo "$result_log"
}

# Run Rundeck job. Return Rundeck job id.
rundeck_run_job() {
    local job_id="$1"
    local data="$2"
    local rundeck_job
    local rc
    local job_status

    if [[ -z $data ]]; then
        rundeck_job="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X POST "${rundeck_server_url}/api/17/job/${job_id}/run?authtoken=${rundeck_api_token}&filter=${host}")"
        rc=$?
    else
        rundeck_job="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X POST "${rundeck_server_url}/api/17/job/${job_id}/run?authtoken=${rundeck_api_token}&filter=${host}" -d "$data")"
        rc=$?
    fi
    if [[ $rc != 0 ]]; then
        echo "$rundeck_job" >&2
        error_exit "ERROR: ${0}(@$LINENO): Rundeck API call failed."
    fi
    echo "$rundeck_job" | jq '.' > /dev/null # Check if this is valid JSON.
    rc=$?
    if [[ $rc != 0 ]]; then
        echo "$rundeck_job" >&2
        error_exit "ERROR: ${0}(@$LINENO): Could not parse Rundeck results."
    fi
    job_status="$(echo "$rundeck_job" | jq '.status' | tr -d '"')"
    if [[ $job_status != "running" ]]; then
        error_exit "ERROR: ${0}(@$LINENO): Rundeck job could not be executed."
    fi
    echo "$rundeck_job" | jq '.id'
}

# Run Rundeck job. Return Rundeck job id.
rundeck_run_job_failok() {
    local rundeck_server_url="$1"
    local rundeck_api_token="$2"
    local node_name="$3"
    local job_id="$4"
    local data="$5"
    local job_status
    local rc
    local rc_total
    local rundeck_job

    if [[ -z $data ]]; then
        rundeck_job="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X POST "${rundeck_server_url}/api/17/job/${job_id}/run?authtoken=${rundeck_api_token}&filter=${node_name}")"
        rc=$?
    else
        rundeck_job="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X POST "${rundeck_server_url}/api/17/job/${job_id}/run?authtoken=${rundeck_api_token}&filter=${node_name}" -d "$data")"
        rc=$?
    fi
    rc_total="$(( rc_total + rc ))"
    echo "$rundeck_job" | jq '.' > /dev/null # Check if this is valid JSON.
    rc=$?
    rc_total="$(( rc_total + rc ))"
    job_status="$(echo "$rundeck_job" | jq '.status' | tr -d '"')"
    if [[ $job_status != "running" ]]; then
        rc=1
    fi
    rc_total="$(( rc_total + rc ))"
    echo "$rundeck_job" | jq '.id'
    return "$rc_total"
}

# Wait for Rundeck job to complete.
rundeck_wait_for_job_to_complete() {
    local execution_id="$1"
    local result
    local rc
    local execution_state

    # Some possible Rundeck execution states: RUNNING, WAITING, SUCCEEDED.

    local i
    for (( i=1; i<=60; i++ )); do
        result="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X GET "${rundeck_server_url}/api/17/execution/${execution_id}/state?authtoken=${rundeck_api_token}")"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "$result" >&2
            error_exit "ERROR: ${0}(@$LINENO): Rundeck API call failed."
        fi
        execution_state="$(echo "$result" | jq '.executionState' | tr -d '"')"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "$result" >&2
            error_exit "ERROR: ${0}(@$LINENO): Could not parse Rundeck results."
        fi

        if [[ $execution_state = "SUCCEEDED" ]]; then
            break
        else
            sleep 5
        fi
    done

    if [[ $execution_state != "SUCCEEDED" ]]; then
        echo "execution_state: $execution_state" >&2
        error_exit "ERROR: ${0}(@$LINENO): Rundeck job is taking too long to complete."
    fi

    echo "$execution_state"
    return 0
}

# Decide on what type of backup to perform.
select_backup_type() {
    if [[ -z "$bkup_type" ]]; then
        # Check if daily or weekly backup should be run.
        if [[ $bkup_dow -eq $weekly_bkup_dow ]]; then
            # Check if it is time to run monthly or yearly backup.
            bkup_y="$(date -d "$start_time_wot" +'%Y')"
            yearly_bkup_exists="$(find "$bkup_dir/" -maxdepth 1 -type d -name "[0-9]*T[0-9]*Z.yearly" | awk -F'/' '{print $NF}' | grep "^$bkup_y")"
            bkup_ym="$(date -d "$start_time_wot" +'%Y%m')"
            monthly_bkup_exists="$(find "$bkup_dir/" -maxdepth 1 -type d -name "[0-9]*T[0-9]*Z.monthly" | awk -F'/' '{print $NF}' | grep "^$bkup_ym")"
            bkup_yw="$(date -d "$start_time_wot" +'%Y%U')"
            weekly_bkup_exists="$(find "$bkup_dir/" -maxdepth 1 -type d -name "[0-9]*T[0-9]*Z.weekly" | awk -F'/' '{print $NF}' | awk -FT '{print $1}' | xargs -i date -d "{}" +'%Y%U' | grep "^$bkup_yw")"
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

# Start MongoDB balancer.
start_balancer() {
    local balancer_state

    if [[ $need_to_start_balancer = "true" ]]; then
        balancer_state="$("$mongo" --quiet "$mongos_host_port" --eval "sh.getBalancerState()")"
        echo "Balancer state: $balancer_state"
        if [[ $balancer_state = "true" ]]; then
            echo "Warning: Balancer state was changed during backup."
        fi
        echo "Start the balancer."
        "$mongo" --quiet "$mongos_host_port" --eval "sh.startBalancer()"
        balancer_state="$("$mongo" --quiet "$mongos_host_port" --eval "sh.getBalancerState()")"
        echo "Balancer state: $balancer_state"
    fi
}

# Stop MongoDB balancer.
stop_balancer() {
    local result

    need_to_start_balancer="true"
    result="$("$mongo" --quiet "$mongos_host_port" --eval "sh.getBalancerState()")"
    echo "Balancer state: $result"
    echo "Stop the balancer..."
    "$mongo" --quiet "$mongos_host_port" --eval "sh.stopBalancer()"
    result="$("$mongo" --quiet "$mongos_host_port" --eval "sh.getBalancerState()")"
    echo "Balancer state: $result"
    if [[ $result != "false" ]]; then
        error_exit "ERROR: ${0}(@$LINENO): Balancer could not be stopped."
    fi
    for (( i=1; i<="$mongodb_is_balancer_running_iterations"; i++ )); do
        result="$("$mongo" --quiet "$mongos_host_port" --eval "sh.isBalancerRunning()")"
        if [[ $result = "false" ]]; then
            break
        fi
        sleep "$mongodb_sleep_seconds_between_is_balancer_running"
    done
    if [[ $result != "false" ]]; then
        error_exit "ERROR: ${0}(@$LINENO): Balancer did not stop."
    fi
}

set -E
set -o pipefail
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

if [[ -z $bkup_date ]]; then
    error_exit "ERROR: ${0}(@$LINENO): bkup_date variable was not set."
fi

# Start backup in daemon mode.
if [[ $command = "start" ]]; then
    select_backup_type
    bkup_path="$bkup_dir/$bkup_date.$bkup_type"
    bkup_pid_file="$bkup_path/backup.pid"
    bkup_status_file="$bkup_path/backup.status.json"
    # Output status in JSON.
    cat <<HERE_DOC
{"start_time":"$start_time","backup_path":"$bkup_path","status":"running"}
HERE_DOC
    exec 1> "$log" 2> "$log" 2> "$log_err"
    main &
# Get backup status.
elif [[ $command = "status" ]]; then
    if [[ -z $bkup_path ]]; then
        bkup_path="$(find "$bkup_dir" -maxdepth 1 -type d -name '[0-9]*T[0-9]*Z.*' | sort | tail -1)"
    fi
    bkup_pid_file="$bkup_path/backup.pid"
    bkup_status_file="$bkup_path/backup.status.json"
    if [[ -f $bkup_pid_file ]] && [[ -f $bkup_status_file ]]; then
        pid="$(cat "$bkup_pid_file")"
        kill -0 "$pid" 2> /dev/null
        rc=$?
        if [[ $rc -eq 0 ]]; then
            cat "$bkup_status_file"
            exit 0
        else
            status="$(jq '.status' < "$bkup_status_file" | tr -d '"')"
            if [[ $status = "completed" ]]; then
                cat "$bkup_status_file"
                exit 0
            fi
            # Output status in JSON.
            cat <<HERE_DOC
{"backup_path":"$bkup_path","status":"failed"}
HERE_DOC
            exit 0
        fi
    fi
    # Output status in JSON.
    cat <<HERE_DOC
{"backup_path":"$bkup_path","status":"unknown"}
HERE_DOC
# Start backup in regular mode.
else
    # Redirect stderr into error log, stdout and stderr into log and terminal.
    exec 1> >(tee -ia "$log") 2> >(tee -ia "$log" >&2) 2> >(tee -ia "$log_err" >&2)
    select_backup_type
    bkup_path="$bkup_dir/$bkup_date.$bkup_type"
    bkup_pid_file="$bkup_path/backup.pid"
    bkup_status_file="$bkup_path/backup.status.json"
    main
fi
