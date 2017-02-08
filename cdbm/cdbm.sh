#!/bin/bash
################################################################################
# Purpose:
#     Manage backup execution via Rundeck.
#
#     This script does not rely on Rundeck to wait for the job to complete. 
#     Instead it starts the backup jobs in daemon mode and then sends status 
#     calls via another Rundeck job to track progress of the backup jobs.
################################################################################

version="1.0.8"

script_start_ts="$(date -u +'%FT%TZ')"
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
        node_name=$1
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

cdbm_mysql_con="$cdbm_mysql --host=$cdbm_host --port=$cdbm_port --no-auto-rehash --silent --skip-column-names $cdbm_db --user=$cdbm_username --password=$cdbm_password"

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
    sql="SELECT node_id FROM node WHERE node_name = '$node_name';"
    node_id="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

    if [[ -z $node_id ]]; then
        if [[ $db_type == "mongodb" ]]; then
            cluster_name="$(sed -r "$cluster_name_sed" <<<"$node_name")"

            sql="SELECT cluster_id FROM cluster WHERE cluster_name = '$cluster_name';"
            cluster_id="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
            rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

            if [[ -z $cluster_id ]]; then
                sql="INSERT INTO cluster (cluster_name) VALUES ('$cluster_name');"
                result="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi

                sql="SELECT cluster_id FROM cluster WHERE cluster_name = '$cluster_name';"
                cluster_id="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi
            fi
        fi

        sql="INSERT INTO node (cluster_id, db_type, node_name, port) VALUES ($cluster_id, '$db_type', '$node_name', $port);"
        result="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
        rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi

        sql="SELECT node_id FROM node WHERE node_name = '$node_name';"
        node_id="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
        rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi
    fi

    sql="INSERT INTO log (node_id, start_time, backup_path, status) VALUES ($node_id, '$start_time', '$backup_path', '$status');"
    result="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi
}

check_for_finished() {
    local bkup_execution_id
    local execution_log
    local execution_state
    local node_id
    local rc
    local result_started
    local status

    sql="SELECT log_id, cluster_id, db_type, node_name, port, start_time, backup_path FROM log JOIN node ON log.node_id = node.node_id WHERE status = 'started';"
    result_started="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi
    # If there are no backups in progress, then exit.
    if [[ -z $result_started ]]; then
        exit 0
    fi

    while read log_id cluster_id db_type node_name port start_date start_time backup_path; do
        if [[ -z $log_id || -z $cluster_id || -z $db_type || -z $node_name || -z $port || -z $start_date || -z $start_time || -z $backup_path ]]; then
            die "Not all the parameters were supplied."
        fi

        # Get execution status.
        bkup_execution_id="$(rundeck_run_job "$rundeck_server_url" "$rundeck_api_token" "$rundeck_job_id" "$node_name" "{\"argString\":\"-command status -backup-path $backup_path\"}")"

        # Wait for Rundeck execution to complete.
        execution_state="$(rundeck_wait_for_job_to_complete "$rundeck_server_url" "$rundeck_api_token" "$bkup_execution_id")"

        # Get log from Rundeck execution.
        execution_log="$(rundeck_get_execution_output_log "$rundeck_server_url" "$rundeck_api_token" "$bkup_execution_id" "$node_name")"
        echo "node_name: $node_name"
        echo "$execution_log"

        status="$(jq '.status' <<<"$execution_log" | tr -d '"')"
        if [[ -z $status ]]; then status="failed"; fi

        if [[ $status = "completed" ]] || [[ $status = "failed" ]]; then
            replset_count="$(jq '.backup_nodes | length' <<<"$execution_log")"
            rc=$?; if [[ $rc -ne 0 ]]; then replset_count=0; fi

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

                sql="SELECT node_id FROM node WHERE node_name = '$replset_node_name';"
                replset_node_id="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi

                if [[ -z $replset_node_id ]]; then
                    sql="INSERT INTO node (cluster_id, db_type, node_name, port) VALUES ($cluster_id, '$db_type', '$replset_node_name', $replset_port);"
                    result="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
                    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi

                    sql="SELECT node_id FROM node WHERE node_name = '$replset_node_name';"
                    replset_node_id="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
                    rc=$?; if [[ $rc -ne 0 ]]; then die "Could not query database. $sql"; fi
                fi

                replset_start_time="$(jq ".backup_nodes[$i].start_time" <<<"$execution_log" | tr -d '"')"
                rc=$?; if [[ $rc -ne 0 ]]; then continue; fi

                replset_end_time="$(jq ".backup_nodes[$i].end_time" <<<"$execution_log" | tr -d '"')"
                rc=$?; if [[ $rc -ne 0 ]]; then continue; fi

                replset_backup_path="$(jq ".backup_nodes[$i].backup_path" <<<"$execution_log" | tr -d '"')"
                rc=$?; if [[ $rc -ne 0 ]]; then continue; fi

                sql="INSERT INTO log (node_id, start_time, end_time, backup_path, status) VALUES ($replset_node_id, '$replset_start_time', '$replset_end_time', '$replset_backup_path', '$status');"
                result="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not insert into database. $sql"; fi
            done

            end_time="$(jq ".end_time" <<<"$execution_log" | tr -d '"')"
            rc=$?; if [[ $rc -ne 0 ]]; then continue; fi

            sql="UPDATE log SET status = '$status', end_time = '$end_time' WHERE log_id = $log_id;"
            result="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
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
                sql="UPDATE log SET status = '$status', end_time = '$script_start_ts' WHERE log_id = $log_id;"
                result="$($cdbm_mysql_con -e "$sql" 2> /dev/null)"
                rc=$?; if [[ $rc -ne 0 ]]; then die "Could not update database. $sql"; fi
            fi
        fi
    done <<<"$result_started"
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
        elif [[ $execution_state = "SUCCEEDED" ]]; then
            echo "$execution_state"
            break
        else
            echo "execution_state: $execution_state" >&2
            die "Rundeck job failed."
        fi
    done
    if [[ $execution_state != "SUCCEEDED" ]]; then
        die "Rundeck job is taking too long to complete."
    fi
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
check_for_finished)
    check_for_finished
    ;;
esac
