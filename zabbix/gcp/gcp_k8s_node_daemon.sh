#!/bin/bash

version=1.2.0

# Zabbix server.
zabbix_server="zabbix-server-or-proxy"
# Host name, which is being monitored in Zabbix.
host="monitored host name as set up in zabbix"
# Custom location of gcpmetrics.
gcpmetrics="python27 /opt/gcpmetrics/gcpmetrics.py"
# GCP metrics time period in minutes.
period_min=2
# Number of tries before giving up on obtaining GCP metrics.
num_tries=20

set -E
set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

shopt -s expand_aliases
alias die='error_exit "ERROR in $0: line $LINENO:"'

usage() {
    cat <<USAGE
Usage:
    $script_name [--lld] project-name region k8s-cluster-name
    $script_name {--version | --help}

Example:
    $script_name my-gcp-project us-central1 my-k8s-cluster

Description:
    Provides GCP (Google Cloud Platform) k8s metrics for use in a monitoring system like Zabbix.

Dependendies:
    These tools need to be installed:
    gcloud        - https://cloud.google.com/sdk/gcloud/
    gcpmetrics    - https://github.com/ingrammicro/gcpmetrics
    jq            - https://stedolan.github.io/jq/
    zabbix_sender

    gcloud key needs to be set up in (replace 'project-name' with actual GCP project name):
    ${script_name/.sh/.project-name.key.json}

Options:
    --lld        Zabbix low lever discovery.
    --version    Display script version.
    --help       Display this help.
USAGE
}

error_exit() {
    echo "$@" >&2
    exit 77
}
trap '[ "$?" -ne 77 ] || exit 77' ERR
trap "error_exit 'Received signal SIGHUP'" SIGHUP
trap "error_exit 'Received signal SIGINT'" SIGINT
trap "error_exit 'Received signal SIGTERM'" SIGTERM

format_metrics() {
    local metrics_data row1_num_columns row2_num_columns ratio
    metrics_data="$1"

    # Take fixed width formatted input.
    # Grab last 3 lines.
    # Count number of columns in 1st and 2nd lines (minus 1 column).
    row1_num_columns="$(echo "$metrics_data" | tail -3 | awk 'NR==1 {print NF - 1}')"
    row2_num_columns="$(echo "$metrics_data" | tail -3 | awk 'NR==2 {print NF - 1}')"
    ratio=$((row2_num_columns / row1_num_columns))

    # Take fixed width formatted input.
    # Grab last 3 lines.
    # Replace space between date and time with 'T'.
    # Add missing headers (to match number of columns in 1st and 2nd row) and remove repeated spaces.
    # Remove trailing spaces.
    # Transpose.
    echo "$metrics_data" | tail -3 | sed 's/\(^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)[ ]/\1T/' | awk -v ratio="$ratio" '
    BEGIN {ORS=""}
    NR==1 {
        for (n=1; n<=NF; n++) {
            if (n==1) {
               printf "%s ", $n
            }
            else {
                for (c=1; c<=ratio; c++) {
                    printf "%s ", $n
                }
            }
        }
        print "\n"
    }
    NR>1 {
        for (n=1; n<=NF; n++) {
            printf "%s ", $n
        }
        print "\n"
    }' | sed 's/ $//' | jq -R . | jq -sr 'map(./" ")|transpose|map(join(" "))[]'
}

while test -n "$1"; do
    case "$1" in
    --help)
        usage
        exit
        ;;
    --version)
        echo "$version"
        exit
        ;;
    --lld)
        lld="yes"
        shift
        ;;
    *)
        if [[ ! $project_name ]]; then
            project_name="$1"
        elif [[ ! $region ]]; then
            region="$1"
        elif [[ ! $cluster_name ]]; then
            cluster_name="$1"
        else
            echo "Error: Too many arguments." >&2
            echo
            usage
            exit 1
        fi
        shift
    esac
done

if [[ ! $project_name || ! $region || ! $cluster_name ]]; then
    echo "Error: Not all of the required arguments were supplied." >&2
    echo
    usage
    exit 1
fi

key_file="$script_dir/gcp_key.${project_name}.json"

for (( c=1; c<="$num_tries"; c++ )); do
    metrics_data="$($gcpmetrics --keyfile "$key_file" --project "$project_name" --query --minutes "$period_min" --metric kubernetes.io/node_daemon/cpu/core_usage_time --resource-filter "cluster_name:$cluster_name")"
    [[ $? -ne 0 ]] && die "Error from gcpmetrics command."

    if echo "$metrics_data" | grep -q 'Empty DataFrame'; then
        if [[ "$c" -eq "$num_tries" ]]; then
            die "No data returned from GCP after $num_tries tries."
        fi
    else
        break
    fi
    sleep 1
done

transposed="$(format_metrics "$metrics_data")"

if [[ "$lld" == "yes" ]]; then
    node_names="$(echo "$transposed" | sed '1d' | awk '{print $1}' | uniq)"
    echo '{'
    echo '  "data": ['
    while read line; do
        echo '    {'
        echo "      \"{#NODE_NAME}\": \"$line\""
        echo '    },'
    done <<<"$node_names" | sed '$ s/,//'
    echo '  ]'
    echo '}'
else
    timestamp="$(echo "$transposed" | awk 'NR==1 {print $3}')"
    epoch="$(date --date="$timestamp" +'%s')"

    zabbix_data="$(
        while read node_name component value; do
            echo "\"$host\" \"k8s_node.$component.cpu.core_usage_time[\\\"$node_name\\\"]\" $epoch $value"
        done < <(sed '1d' <<<"$transposed")
    )"
    echo "$zabbix_data" | zabbix_sender --zabbix-server "$zabbix_server" --with-timestamps --input-file -
fi
