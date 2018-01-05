#!/bin/bash

# Purpose:
#     Set up DynamoDB cross-region replication.
# Usage:
#     Run script with --help option to get usage.

version="1.0.1"

set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

table="$1"
region_source="$2"
region_destination="$3"

replication_jar="$script_dir/dynamodb-cross-region-replication-1.1.0.jar"
task_name="_-Table-_${table}_-To-_${region_destination}"
job_dir="$script_dir/$task_name"
endpoint_source="https://dynamodb.${region_source}.amazonaws.com"
endpoint_destination="https://dynamodb.${region_destination}.amazonaws.com"

function usage {
    echo "Usage:"
    echo "    $script_name table region_source region_destination"
    echo
    echo "Example:"
    echo "    $script_name Prod_MyTable us-east-1 us-west-2"
    echo
    echo "Description:"
    echo "    -h, --help    Show this help."
    exit 1
}

if [[ $1 == "--help" || $1 == "-h" || -z $3 ]]; then
    usage
fi

echo "Creating directory: $job_dir"
mkdir "$job_dir"
rc=$?
if [[ $rc -gt 0 ]]; then
    echo "Error: Failed to create directory."
    exit 1
fi
echo

cd "$job_dir" || exit 1

echo "Starting replication task: $task"
nohup java -jar "$replication_jar" --sourceEndpoint "$endpoint_source" --sourceTable "$table" --destinationEndpoint "$endpoint_destination" --destinationTable "$table" --taskName "$task_name" &
ps -ef | grep java | grep -- "--taskName $task_name"
echo

echo "Replication tracking table will be created at source region. It will start with 10 read capacity and 10 write capacity."
echo "Replication tracking table name: DynamoDBCrossRegionReplication${task_name}"
