set -E
set -o pipefail#!/bin/bash

version=1.0.0

# Set custom location of gcpmetrics.
gcpmetrics="python /github/gcpmetrics/gcpmetrics/gcpmetrics.py"

set -E
set -o pipefail
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="$(basename "$0")"

shopt -s expand_aliases
alias die='error_exit "ERROR in $0: line $LINENO:"'

usage() {
    cat <<USAGE
Usage:
    $script_name project-name region k8s-cluster-name
    $script_name {--version | --help}

Example:
    $script_name my-gcp-project us-central1 my-k8s-cluster

Description:
    Provides GCP (Google Cloud Platform) k8s metrics for use in a monitoring system like Zabbix.

Dependendies:
    These tools need to be installed:
    gcloud     - https://cloud.google.com/sdk/gcloud/
    gcpmetrics - https://github.com/ingrammicro/gcpmetrics
    jq         - https://stedolan.github.io/jq/

    gcloud key needs to be set up in (replace project-name with actual GCP project name):
    ${script_name/.sh/.project-name.key.json}

Options:
    --version                  Display script version.
    --help                     Display this help.
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

set_project() {
    local project_name
    project_name="$1"
    gcloud config set project "$project_name" &> /dev/null
    [[ $? -ne 0 ]] && die "Error from gcloud command."
}

get_zones_and_groups() {
    local region cluster_name
    region="$1"
    cluster_name="$2"
    gcloud container clusters describe --region "$region" "$cluster_name" --format="json" | jq -r '.nodePools[].instanceGroupUrls[]' | awk -F'/' '{print $9, $11}'
    [[ $? -ne 0 ]] && die "Error from gcloud command."
}

list_instances_from_zones_and_groups() {
    local zones_and_groups
    zones_and_groups="$1"
    while read zone group; do
        gcloud compute instance-groups list-instances --zone "$zone" "$group" --format=json | jq -r '.[].instance' | awk -F'/' '{print $11}'
        [[ $? -ne 0 ]] && die "Error from gcloud command."
    done <<< "$zones_and_groups"
}

get_field_widths() {
    # Get field widths from columns in fixed width format delimited by space.

    local lines
    lines="$1"
    # 1. Conversion for being able to find longest fields in fixed with format with some fields being blank.
    # 2. Replace double spaces with a single space and filler character.
    # 3. Get field widths.
    echo "$lines" | awk '
    BEGIN {FS=""; ORS=""}
    {
        for (i=1; i<=NF; i++) {
            a[NR,i] = $i
        }
    }
    NF>p { p = NF }
    END {
        for (j=1; j<=p; j++) {
            str=a[1,j]
            for (i=2; i<=NR; i++) {
                if (a[i,j]!=" ") {
                    str=a[i,j]
                }
            }
            print str
        }
    }' | sed 's/  \([^ ]\)/ X\1/g' | awk '
    BEGIN {ORS=" "}
    {
        for (n=1; n<=NF; n++) {
            if (n==1) {
               print length($n)
            }
            else {
               print length($n) + 1
            }
        }
    }' | sed 's/.$//'
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

#set_project "$project_name"

#zones_and_groups="$(get_zones_and_groups "$region" "$cluster_name")"

#instances="$(list_instances_from_zones_and_groups "$zones_and_groups")"

#date +%s
#for instance in $instances; do
#    gcpmetrics --keyfile keyfile.json --project my-gcp-project --query --minutes 2 --metric kubernetes.io/node_daemon/cpu/core_usage_time --resource-filter cluster_name:my-cluster,node_name:$instance
#done
#date +%s

key_file="$script_dir/${script_name/.sh/.${project_name}.key.json}"
result="$($gcpmetrics --keyfile "$key_file" --project "$project_name" --query --minutes 2 --metric kubernetes.io/node_daemon/cpu/core_usage_time --resource-filter "cluster_name:$cluster_name")"
[[ $? -ne 0 ]] && die "Error from gcpmetrics command."

# Grab 3 lines starting with node_name. Add T between date and time.
result2="$(echo "$result" | grep -A 2 '^node_name' | sed 's/\(^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)[ ]/\1T/')"

field_widths="$(get_field_widths "$result2")"

echo "$field_widths"

echo "$result2" | awk '{for(i=1;i<=NF;i++)if($i~/^ *$/)$i=0}1' FIELDWIDTHS="$field_widths"
