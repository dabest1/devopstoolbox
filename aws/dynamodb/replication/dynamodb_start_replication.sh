#!/bin/bash

# Purpose:
#     Start DynamoDB replication tasks which have been pre-configured.

version="1.0.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

region_source="us-east-1"
replication_jar="/data/dynamodb/replication/dynamodb-cross-region-replication-1.1.0.jar"

cd "$script_dir" || { echo "Error."; exit 1; }
for task_name in $(ls -d _-Table-_*); do
    table=$(echo "$task_name" | awk -F'_-Table-_|_-To-_' '{print $2}')
    region_destination=$(echo "$task_name" | awk -F'_-Table-_|_-To-_' '{print $3}')
    job_dir="$script_dir/$task_name"
    endpoint_source="https://dynamodb.${region_source}.amazonaws.com"
    endpoint_destination="https://dynamodb.${region_destination}.amazonaws.com"
    echo "task_name: $task_name"
    echo "table: $table"
    echo "region_source: $region_source"
    echo "region_destination: $region_destination"

    process=$(ps -ef | grep "[d]ynamodb-cross-region-replication" | grep -- "--taskName $task_name")
    if [[ ! -z $process ]]; then
        echo "Warning: Task is already running."
    else
        echo "Starting replication task..."
        cd "$job_dir" || { echo "Error."; exit 1; }
        #nohup java -jar "../$replication_jar" --sourceEndpoint "$endpoint_source" --sourceTable "$table" --destinationEndpoint "$endpoint_destination" --destinationTable "$table" --taskName "$task_name" &
        java -jar "$replication_jar" --sourceEndpoint "$endpoint_source" --sourceTable "$table" --destinationEndpoint "$endpoint_destination" --destinationTable "$table" --taskName "$task_name" &
        ps -ef | grep java | grep -- "--taskName $task_name"
        echo "Done."
        cd "$script_dir" || { echo "Error."; exit 1; }
    fi
    echo
done
