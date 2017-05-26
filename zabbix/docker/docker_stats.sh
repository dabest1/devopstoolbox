#!/usr/bin/env bash

################################################################################
# Purpose:
#     Output selected metrics from docker stats command to be used by alerting software such as Zabbix.
################################################################################


version="1.0.0"
metric_selected="$1"

to_bytes() {
    # Accepts "value unit", multiple items are separated by new line.
    # docker uses multiplier of 1000, not 1024.

    while read -r value unit; do
        case $unit in
        B)
            multiplier=1
            ;;
        kB)
            multiplier=1000
            ;;
        MB)
            multiplier=1000000
            ;;
        GB)
            multiplier=1000000000
            ;;
        TB)
            multiplier=1000000000000
            ;;
        PB)
            multiplier=1000000000000000
            ;;
        esac
        echo "$value * $multiplier / 1" | bc
    done <<<"$metrics"
}

containers="$(docker ps --format="{{.Names}}")"
stats_output="$(docker stats --no-stream $containers)"

case "$metric_selected" in
cpu)
    metrics="$(echo "$stats_output" | sed '1d' | awk '{print $2}' | tr -d '%')"
    paste <(echo "$containers") <(echo "$metrics")
    ;;
mem)
    metrics="$(echo "$stats_output" | sed '1d' | awk '{print $3, $4}')"
    paste <(echo "$containers") <(to_bytes "$metrics")
    ;;
mem_limit)
    metrics="$(echo "$stats_output" | sed '1d' | awk '{print $6, $7}')"
    paste <(echo "$containers") <(to_bytes "$metrics")
    ;;
mem_pct)
    metrics="$(echo "$stats_output" | sed '1d' | awk '{print $8}' | tr -d '%')"
    paste <(echo "$containers") <(echo "$metrics")
    ;;
net_in)
    metrics="$(echo "$stats_output" | sed '1d' | awk '{print $9, $10}')"
    paste <(echo "$containers") <(to_bytes "$metrics")
    ;;
net_out)
    metrics="$(echo "$stats_output" | sed '1d' | awk '{print $12, $13}')"
    paste <(echo "$containers") <(to_bytes "$metrics")
    ;;
block_in)
    metrics="$(echo "$stats_output" | sed '1d' | awk '{print $14, $15}')"
    paste <(echo "$containers") <(to_bytes "$metrics")
    ;;
block_out)
    metrics="$(echo "$stats_output" | sed '1d' | awk '{print $17, $18}')"
    paste <(echo "$containers") <(to_bytes "$metrics")
    ;;
*)
    echo "Error: unknown metric."
    exit 1
esac
