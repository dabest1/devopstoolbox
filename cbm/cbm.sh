#!/bin/bash
################################################################################
# Purpose:
#     Central Backup Manager:
#     Manage backup execution via Rundeck.
#
#     This script does not rely on Rundeck to wait for the job to complete. 
#     Instead it starts the backup jobs in daemon mode and then sends status 
#     calls via another Rundeck job to track progress of the backup jobs.
################################################################################

version="1.6.0"

script_start_ts="$(date -u +'%FT%TZ')"
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
    backup_started)
        command="$1"
        shift
        db_type=$1
        shift
        node_name=$1
        shift
        execid=$1
        shift
        ;;
    restore_started)
        command="$1"
        shift
        db_type=$1
        shift
        running_on_node_name=$1
        shift
        execid=$1
        shift
        ;;
    check_for_finished)
        command="$1"
        shift
        ;;
    check_for_finished_restore)
        command="$1"
        shift
        ;;
    run_random_restore)
        command="$1"
        shift
        ;;
    *)
        echo "Invalid option: $1" >&2
        exit 1
    esac
done

# Variables.

cbm_mysql_con="$cbm_mysql --host=$cbm_host --port=$cbm_port --no-auto-rehash --silent --skip-column-names $cbm_db --user=$cbm_username --password=$cbm_password"

# Functions.

shopt -s expand_aliases
alias die='error_exit "ERROR: $0: line $LINENO:"'

backup_started() {
    # TODO: Need to pass port number to this script.
    if [[ $db_type == "mongodb" ]]; then
        port="27017"
    fi

    rundeck_log="$(rundeck_get_execution_output_log "$rundeck_server_url" "$rundeck_api_token" "$execid" "$node_name")"
    start_time="$(jq '.start_time' <<<"$rundeck_log" | tr -d '"')"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not parse Rundeck results."; fi
    backup_path="$(jq '.backup_path' <<<"$rundeck_log" | tr -d '"')"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not parse Rundeck results."; fi
    status="$(jq '.status' <<<"$rundeck_log" | tr -d '"')"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not parse Rundeck results."; fi

    # TODO: Need to handle "Warning: Using a password on the command line interface can be insecure." warning.
    sql="SELECT node_id FROM cbm_node WHERE node_name = '$node_name';"
    node_id="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

    if [[ -z $node_id ]]; then
        if [[ $db_type == "mongodb" ]]; then
            cluster_name="$(sed -r "$cluster_name_sed" <<<"$node_name")"

            sql="SELECT cluster_id FROM cbm_cluster WHERE cluster_name = '$cluster_name';"
            cluster_id="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
            rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

            if [[ -z $cluster_id ]]; then
                sql="INSERT INTO cbm_cluster (cluster_name) VALUES ('$cluster_name');"
                result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi

                sql="SELECT cluster_id FROM cbm_cluster WHERE cluster_name = '$cluster_name';"
                cluster_id="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi
            fi
        fi

        sql="INSERT INTO cbm_node (cluster_name_id, db_type, node_name, port) VALUES ($cluster_id, '$db_type', '$node_name', $port);"
        result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
        rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi

        sql="SELECT node_id FROM cbm_node WHERE node_name = '$node_name';"
        node_id="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
        rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi
    fi

    sql="INSERT INTO cbm_backup (node_name_id, start_time, backup_path, status) VALUES ($node_id, '$start_time', '$backup_path', '$status');"
    result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi
}

# Check for finished backup.
check_for_finished() {
    local bkup_execution_id
    local execution_log
    local execution_state
    local node_id
    local rc
    local result_started
    local status

    sql="SELECT backup_id, cluster_name_id, db_type, node_name, port, start_time, backup_path FROM cbm_backup JOIN cbm_node ON cbm_backup.node_name_id = cbm_node.node_id WHERE status = 'started';"
    result_started="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi
    # If there are no backups in progress, then exit.
    if [[ -z $result_started ]]; then
        exit 0
    fi

    while read backup_id cluster_id db_type node_name port start_date start_time backup_path; do
        if [[ -z $backup_id || -z $cluster_id || -z $db_type || -z $node_name || -z $port || -z $start_date || -z $start_time || -z $backup_path ]]; then
            die "Not all the parameters were supplied."
        fi

        # Get execution status.
        bkup_execution_id="$(rundeck_run_job "$rundeck_server_url" "$rundeck_api_token" "$rundeck_job_id_backup" "$node_name" "{\"argString\":\"-command status -backup-path $backup_path\"}")"

        # Wait for Rundeck execution to complete.
        execution_state="$(rundeck_wait_for_job_to_complete "$rundeck_server_url" "$rundeck_api_token" "$bkup_execution_id")"

        # Get log from Rundeck execution.
        execution_log="$(rundeck_get_execution_output_log "$rundeck_server_url" "$rundeck_api_token" "$bkup_execution_id" "$node_name")"
        echo "node_name: $node_name"
        echo "execution_log: $execution_log"
        echo "execution_state: $execution_state"

        status="$(jq '.status' <<<"$execution_log" | tr -d '"')"
        if [[ -z $status ]]; then status="failed"; fi

        if [[ $status = "completed" ]] || [[ $status = "failed" ]]; then
            replset_count="$(jq '.backup_nodes | length' <<<"$execution_log")"
            rc=$?
            if [[ $rc -ne 0 || -z $execution_log ]]; then
                replset_count=0
            fi

            local i
            local replset_backup_path
            local replset_end_time
            local replset_node
            local replset_node_id
            local replset_node_name
            local replset_port
            local replset_start_time
            local result
            for ((i=0; i<"$replset_count"; i++)); do
                replset_node="$(jq ".backup_nodes[$i].node" <<<"$execution_log" | tr -d '"')"
                rc=$?; if [[ $rc -ne 0 ]]; then continue; fi

                replset_node_name="$(awk -F: '{print $1}' <<<"$replset_node")"
                replset_port="$(awk -F: '{print $2}' <<<"$replset_node")"

                sql="SELECT node_id FROM cbm_node WHERE node_name = '$replset_node_name';"
                replset_node_id="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

                if [[ -z $replset_node_id ]]; then
                    sql="INSERT INTO cbm_node (cluster_name_id, db_type, node_name, port) VALUES ($cluster_id, '$db_type', '$replset_node_name', $replset_port);"
                    result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
                    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi

                    sql="SELECT node_id FROM cbm_node WHERE node_name = '$replset_node_name';"
                    replset_node_id="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
                    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi
                fi

                replset_start_time="$(jq ".backup_nodes[$i].start_time" <<<"$execution_log" | tr -d '"')"
                rc=$?; if [[ $rc -ne 0 ]]; then continue; fi

                replset_end_time="$(jq ".backup_nodes[$i].end_time" <<<"$execution_log" | tr -d '"')"
                rc=$?; if [[ $rc -ne 0 ]]; then continue; fi

                replset_backup_path="$(jq ".backup_nodes[$i].backup_path" <<<"$execution_log" | tr -d '"')"
                rc=$?; if [[ $rc -ne 0 ]]; then continue; fi

                sql="INSERT INTO cbm_backup (node_name_id, start_time, end_time, backup_path, status) VALUES ($replset_node_id, '$replset_start_time', '$replset_end_time', '$replset_backup_path', '$status');"
                result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi
            done

            end_time="$(jq ".end_time" <<<"$execution_log" | tr -d '"')"
            rc=$?; if [[ $rc -ne 0 ]]; then continue; fi
            sql="UPDATE cbm_backup SET status = '$status', end_time = '$end_time' WHERE backup_id = $backup_id;"
            result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
            rc=$?; if [[ $rc -ne 0 ]]; then die "Could not update database. $sql"; fi
        elif [[ $status = "started" ]] || [[ $status = "running" ]] || [[ $status = "unknown" ]]; then
            start_epoch_time="$(date -u -d "$start_date $start_time" +"%s")"
            script_start_epoch_time="$(date -u -d "$script_start_ts" +"%s")"
            backup_duration=$(( $script_start_epoch_time - $start_epoch_time ))
            # Backup should be considered failed if it took longer than backup timeout seconds. If status is uknown, set it as unknown.
            if [[ $backup_duration -gt $backup_timeout ]]; then
                if [[ $status = "started" ]] || [[ $status = "running" ]]; then
                    status="failed"
                fi
                sql="UPDATE cbm_backup SET status = '$status', end_time = '$script_start_ts' WHERE backup_id = $backup_id;"
                result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not update database. $sql"; fi
            fi
        fi
    done <<<"$result_started"
}

# Check for finished restore.
check_for_finished_restore() {
    local rc
    local result_running
    local sql

    sql="SELECT restore_id, running_on_node, start_time, restore_path FROM cbm_restore;"
    result_running="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

    # If there are no restores in progress, then exit.
    if [[ -z $result_running ]]; then
        exit 0
    fi

    while read -r restore_id running_on_node start_date start_time restore_path; do
        if [[ -z $restore_id || -z $running_on_node || -z $start_date || -z $start_time || -z $restore_path ]]; then
            die "Not all the parameters were supplied."
        fi

        # Get execution status.
        restore_execution_id="$(rundeck_run_job "$rundeck_server_url" "$rundeck_api_token" "$rundeck_job_id_restore_status" "$running_on_node" "{\"argString\":\"-command status -restore-path $restore_path\"}")"

        # Wait for Rundeck execution to complete.
        execution_state="$(rundeck_wait_for_job_to_complete "$rundeck_server_url" "$rundeck_api_token" "$restore_execution_id")"

        # Get log from Rundeck execution.
        execution_log="$(rundeck_get_execution_output_log "$rundeck_server_url" "$rundeck_api_token" "$restore_execution_id" "$running_on_node")"
        echo "running_on_node: $running_on_node"
        echo "execution_log: $execution_log"
        echo "execution_state: $execution_state"

        status="$(jq '.status' <<<"$execution_log" | tr -d '"')"
        if [[ -z $status ]]; then status="failed"; fi

        if [[ $status = "completed" ]] || [[ $status = "failed" ]]; then
            end_time="$(jq ".end_time" <<<"$execution_log" | tr -d '"')"
            rc=$?; if [[ $rc -ne 0 ]]; then continue; fi

            sql="UPDATE cbm_restore SET status = '$status', end_time = '$end_time' WHERE restore_id = $restore_id;"
            result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
            rc=$?; if [[ $rc -ne 0 ]]; then die "Could not update database. $sql"; fi
        elif [[ $status = "running" ]] || [[ $status = "unknown" ]]; then
            start_epoch_time="$(date -u -d "$start_date $start_time" +"%s")"
            script_start_epoch_time="$(date -u -d "$script_start_ts" +"%s")"
            restore_duration=$(( $script_start_epoch_time - $start_epoch_time ))
            # Restore should be considered failed if it took longer than timeout seconds. If status is uknown, set it as unknown.
            if [[ $restore_duration -gt $restore_timeout ]]; then
                if [[ $status = "started" ]] || [[ $status = "running" ]]; then
                    status="failed"
                fi
                sql="UPDATE cbm_restore SET status = '$status', end_time = '$script_start_ts' WHERE restore_id = $restore_id;"
                result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not update database. $sql"; fi
            fi
        fi
    done <<<"$result_running"
}

error_exit() {
    echo "$@" >&2
    exit 77
}

# Get output from Rundeck execution.
rundeck_get_execution_output() {
    local rundeck_server_url="$1"
    local rundeck_api_token="$2"
    local execution_id="$3"
    local node_name="$4"
    local rc
    local result
    local result_formatted

    result="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X GET "${rundeck_server_url}/api/17/execution/${execution_id}/output/node/${node_name}?authtoken=${rundeck_api_token}")"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "$result" >&2
        die "Rundeck API call failed."
    fi
    result_formatted="$(echo "$result" | jq '.')"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "$result" >&2
        die "Could not parse Rundeck results."
    fi
    echo "$result_formatted"
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
        die "Rundeck API call failed."
    fi
    result_log="$(echo "$result" | jq '.entries[].log' | sed 's/^"//;s/"$//;s/\\"/"/g')"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "$result" >&2
        die "Could not parse Rundeck results."
    fi
    echo "$result_log"
}

# Run Rundeck job. Return Rundeck job id.
rundeck_run_job() {
    local rundeck_server_url="$1"
    local rundeck_api_token="$2"
    local job_id="$3"
    local node_name="$4"
    local data="$5"
    local job_status
    local rc
    local rundeck_job

    if [[ -z $data ]]; then
        rundeck_job="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X POST "${rundeck_server_url}/api/17/job/${job_id}/run?authtoken=${rundeck_api_token}&filter=${node_name}")"
        rc=$?
    else
        rundeck_job="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X POST "${rundeck_server_url}/api/17/job/${job_id}/run?authtoken=${rundeck_api_token}&filter=${node_name}" -d "$data")"
        rc=$?
    fi
    if [[ $rc != 0 ]]; then
        echo "$rundeck_job" >&2
        die "Rundeck API call failed."
    fi
    echo "$rundeck_job" | jq '.' > /dev/null # Check if this is valid JSON.
    rc=$?
    if [[ $rc != 0 ]]; then
        echo "$rundeck_job" >&2
        die "Could not parse Rundeck results."
    fi
    job_status="$(echo "$rundeck_job" | jq '.status' | tr -d '"')"
    if [[ $job_status != "running" ]]; then
        die "Rundeck job could not be executed."
    fi
    echo "$rundeck_job" | jq '.id'
}

# Wait for Rundeck job to complete.
rundeck_wait_for_job_to_complete() {
    local rundeck_server_url="$1"
    local rundeck_api_token="$2"
    local execution_id="$3"
    local execution_state
    local i
    local rc
    local result

    for (( i=1; i<=60; i++ )); do
        result="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X GET "${rundeck_server_url}/api/17/execution/${execution_id}/state?authtoken=${rundeck_api_token}")"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "$result" >&2
            die "Rundeck API call failed."
        fi
        execution_state="$(echo "$result" | jq '.executionState' | tr -d '"')"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "$result" >&2
            die "Could not parse Rundeck results."
        fi
        if [[ $execution_state = "RUNNING" || $result = '{"error":"pending"}' ]]; then
            sleep 5
        elif [[ $execution_state = "SUCCEEDED" || $execution_state = "FAILED" ]]; then
            echo "$execution_state"
            break
        else
            echo "execution_state: $execution_state" >&2
            die "Rundeck job failed."
        fi
    done
    if [[ $execution_state != "SUCCEEDED" ]] && [[ $execution_state != "FAILED" ]]; then
        die "Rundeck job is taking too long to complete."
    fi
}

# Select a random completed backup and restore it.
run_random_restore() {
    local sql
    local completed_backups
    local rc
    local completed_backups_cnt
    local random_backup_num
    local random_backup
    local running_restores

    sql="SELECT running_on_node FROM cbm_restore WHERE status = 'running';"
    running_restores="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

    # Exit if there is already a restore running.
    if [[ ! -z $running_restores ]]; then
        exit 0
    fi

    sql="SELECT node_name, start_time, backup_path FROM cbm_backup JOIN cbm_node ON node_name_id = node_id WHERE start_time > DATE_SUB(CURDATE(), INTERVAL 2 DAY) AND start_time < DATE_SUB(CURDATE(), INTERVAL 1 DAY) AND status = 'completed';"
    completed_backups="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

    completed_backups_cnt="$(echo "$completed_backups" | wc -l)"
    random_backup_num="$(($RANDOM % $completed_backups_cnt + 1))"
    random_backup="$(echo "$completed_backups" | sed -n "${random_backup_num}p")"

    while read -r node_name start_time_dt start_time_tm backup_path; do
        db_type="mongodb"
        backup_to_restore="$(basename "$backup_path")"
        s3_bucket_path="$s3_bucket/$db_type/$node_name"
        echo "Start restore job via Rundeck."
        echo "node_name: $node_name"
        echo "backup_to_restore: $backup_to_restore"
        echo "s3_bucket_path: $s3_bucket_path"
        echo "s3_profile: $s3_profile"
        restore_execution_id="$(rundeck_run_job "$rundeck_server_url" "$rundeck_api_token" "$rundeck_job_id_restore" "$restore_node" "{\"argString\":\"-command start -backup_to_restore $backup_to_restore -s3_bucket_path $s3_bucket_path -s3_profile $s3_profile\"}")"
    done <<<"$random_backup"
}

restore_started() {
    # TODO: Need to pass port number to this script.
    if [[ $db_type == "mongodb" ]]; then
        port="27017"
    fi

    rundeck_log="$(rundeck_get_execution_output_log "$rundeck_server_url" "$rundeck_api_token" "$execid" "$running_on_node_name")"
    start_time="$(jq '.start_time' <<<"$rundeck_log" | tr -d '"')"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not parse Rundeck results."; fi
    backup_node_name="$(jq '.node_name' <<<"$rundeck_log" | tr -d '"')"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not parse Rundeck results."; fi
    backup_start_time="$(jq '.backup_start_time' <<<"$rundeck_log" | tr -d '"')"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not parse Rundeck results."; fi
    status="$(jq '.status' <<<"$rundeck_log" | tr -d '"')"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not parse Rundeck results."; fi
    restore_path="$(jq '.restore_path' <<<"$rundeck_log" | tr -d '"')"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not parse Rundeck results."; fi

    # TODO: Need to handle "Warning: Using a password on the command line interface can be insecure." warning.
    sql="SELECT backup_id FROM cbm_backup WHERE node_name_id = (SELECT node_id FROM cbm_node WHERE node_name = '$backup_node_name') AND start_time = '$backup_start_time';"
    backup_id="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

    sql="SELECT node_id FROM cbm_node WHERE node_name = '$running_on_node_name';"
    running_on_node_id="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

    sql="INSERT INTO cbm_restore (running_on_node, backup_id, start_time, restore_path, status) VALUES ('$running_on_node_name', $backup_id, '$start_time', '$restore_path', '$status');"
    result="$($cbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi
}

set -E
set -o pipefail
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

case "$command" in
backup_started)
    backup_started
    ;;
restore_started)
    restore_started
    ;;
check_for_finished)
    check_for_finished
    ;;
check_for_finished_restore)
    check_for_finished_restore
    ;;
run_random_restore)
    run_random_restore
    ;;
esac
