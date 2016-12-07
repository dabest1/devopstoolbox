#!/bin/bash
################################################################################
# Purpose:
#     Manage backup execution via Rundeck.
#
#     This script does not rely on Rundeck to wait for the job to complete. 
#     Instead it starts the backup jobs in daemon mode and then sends status 
#     calls via another Rundeck job to track progress of the backup jobs.
################################################################################

version="1.0.0"

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
    backup_started)
        command="$1"
        shift
        db_type=$1
        shift
        nodename=$1
        shift
        execid=$1
        shift
        ;;
    check_for_finished)
        command="$1"
        shift
        ;;
    *)
        echo "Invalid option." >&2
        exit 1
    esac
done

# Variables.

if [[ -z $nodename ]]; then
    log="$script_dir/cdbm.log"
    log_err="$script_dir/cdbm.err"
else
    log="$script_dir/cdbm.$nodename.log"
    log_err="$script_dir/cdbm.$nodename.err"
fi
cdbm_mysql_con="$cdbm_mysql --host=$cdbm_host --port=$cdbm_port --no-auto-rehash --silent --skip-column-names $cdbm_db --user=$cdbm_username --password=$cdbm_password"
rundeck_status_check_iterations=432
rundeck_sleep_seconds_between_status_checks=300
mongodb_is_balancer_running_iterations=720
mongodb_sleep_seconds_between_is_balancer_running=5

declare -A replset_bkup_execution_id
declare -A replset_bkup_path

# Functions.

backup_started() {
    #echo "Time started: $start_time"

    # TODO: Need to pass port number to this script.
    if [[ $db_type == "mongodb" ]]; then
        port="27017"
    fi

    rundeck_log="$(rundeck_get_execution_output_log "$rundeck_server_url" "$rundeck_api_token" "$execid" "$nodename")"
    start_time="$(jq '.start_time' <<<"$rundeck_log" | tr -d '"')"
    backup_path="$(jq '.backup_path' <<<"$rundeck_log" | tr -d '"')"
    status="$(jq '.status' <<<"$rundeck_log" | tr -d '"')"

    # TODO: Need to handle "Warning: Using a password on the command line interface can be insecure." warning.
    result_node_id="$($cdbm_mysql_con -e "SELECT node_id FROM node WHERE nodename = '$nodename';" 2> /dev/null)"
    rc=$?
    if [[ $rc -ne 0 ]]; then error_exit; fi

    if [[ -z $result_node_id ]]; then
        result="$($cdbm_mysql_con -e "INSERT INTO node (db_type, nodename, port) VALUES ('$db_type', '$nodename', '$port');" 2> /dev/null)"
        rc=$?
        if [[ $rc -ne 0 ]]; then error_exit; fi

        result_node_id="$($cdbm_mysql_con -e "SELECT node_id FROM node WHERE nodename = '$nodename';" 2> /dev/null)"
        rc=$?
        if [[ $rc -ne 0 ]]; then error_exit; fi
    fi

    result="$($cdbm_mysql_con -e "INSERT INTO log (node_id, start_time, backup_path, status) VALUES ('$result_node_id', '$start_time', '$backup_path', '$status');" 2> /dev/null)"
    rc=$?
    if [[ $rc -ne 0 ]]; then error_exit; fi
}

check_for_finished() {
    local bkup_execution_id
    local execution_log
    local execution_state
    local rc
    local replset_backup_paths
    local replset_nodes
    local result_started

    result_started="$($cdbm_mysql_con -e "SELECT nodename, port, start_time, backup_path FROM log JOIN node ON log.node_id = node.node_id WHERE status = 'started';" 2> /dev/null)"
    rc=$?
    if [[ $rc -ne 0 ]]; then error_exit; fi

    while read node_name port start_date start_time backup_path; do
        echo "From DB: $node_name, $port, $start_date, $start_time, $backup_path"

        # Get execution status.
        bkup_execution_id="$(rundeck_run_job "$rundeck_server_url" "$rundeck_api_token" "$rundeck_job_id" "$node_name" "{\"argString\":\"-command status -backup-path $backup_path\"}")"

        # Wait for Rundeck execution to complete.
        execution_state="$(rundeck_wait_for_job_to_complete "$rundeck_server_url" "$rundeck_api_token" "$bkup_execution_id")"

        # Get log from Rundeck execution.
        execution_log="$(rundeck_get_execution_output_log "$rundeck_server_url" "$rundeck_api_token" "$bkup_execution_id" "$node_name")"
        echo "execution_log: $execution_log"

        replset_nodes="$(jq '.backup_nodes[].node' <<<"$execution_log" | tr -d '"')"
        rc=$?; if [[ $rc -ne 0 ]]; then continue; fi
        echo "replset_nodes: $replset_nodes"
        replset_backup_paths="$(jq '.backup_nodes[].backup_path' <<<"$execution_log" | tr -d '"')"
        rc=$?; if [[ $rc -ne 0 ]]; then continue; fi
        echo "replset_backup_paths: $replset_backup_paths"

        if [[ $status = "completed" ]]; then
            echo "status: $status"
            continue
        else
            echo DEBUG else
        fi
    done <<<"$result_started"
}

error_exit() {
    echo
    echo "$@" >&2
    start_balancer
    if [[ ! -z $mail_on_error ]]; then
        mail -s "Error - MongoDB Backup $HOSTNAME" "$mail_on_error" < "$log"
    fi
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
        error_exit "ERROR: ${0}(@$LINENO): Rundeck API call failed."
    fi
    result_formatted="$(echo "$result" | jq '.')"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "$result" >&2
        error_exit "ERROR: ${0}(@$LINENO): Could not parse Rundeck results."
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

# Wait for Rundeck job to complete.
rundeck_wait_for_job_to_complete() {
    local rundeck_server_url="$1"
    local rundeck_api_token="$2"
    local execution_id="$3"
    local execution_state
    local i
    local rc

    for (( i=1; i<=60; i++ )); do
        local result="$(curl --silent --show-error -H "Accept:application/json" -H "Content-Type:application/json" -X GET "${rundeck_server_url}/api/17/execution/${execution_id}/state?authtoken=${rundeck_api_token}")"
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
        if [[ $execution_state = "RUNNING" ]]; then
            sleep 5
        elif [[ $execution_state = "SUCCEEDED" ]]; then
            echo "$execution_state"
            break
        else
            echo "execution_state: $execution_state" >&2
            error_exit "ERROR: ${0}(@$LINENO): Rundeck job failed."
        fi
    done
    if [[ $execution_state != "SUCCEEDED" ]]; then
        error_exit "ERROR: ${0}(@$LINENO): Rundeck job is taking too long to complete."
    fi
}

set -E
set -o pipefail
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

#if [[ $command = "backup_started" ]]; then
#    exec 1>> "$log" 2>> "$log"
#    main &
#fi

#exec 1>> "$log" 2>> "$log"
case "$command" in
backup_started)
    backup_started
    ;;
check_for_finished)
    check_for_finished
    ;;
esac