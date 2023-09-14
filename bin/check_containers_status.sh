#!/usr/bin/env bash
# shellcheck disable=SC2155

set -e

if ! command -v docker >/dev/null; then
    echo "docker: command not found"
    exit 1
fi

all_containers=$(docker ps --all --format '{{.Names}}')
current_timestamp=$(date +%s)

list_containers () {
    for pattern in "${@}"; do
        while IFS= read -r line; do
            echo "$line"
        done < <(echo "$all_containers" | grep -E "$pattern")
    done
}

get_container_info () {
    local container_name=$1
    docker inspect --format '{{.State.Status}} {{.State.StartedAt}} {{.State.FinishedAt}} {{.State.Pid}} {{.Config.Image}} {{.State.ExitCode}}' "$container_name"
}

calculate_hours () {
    local given_timestamp=$(date -d "$1" +%s)
    local current_timestamp=$(date +%s)
    local time_difference=$((current_timestamp - given_timestamp))
    local hours=$(echo "scale=1; $time_difference / 3600.0" | bc)
    printf "%.2f\n" "$hours"
}

get_container_status_description () {
    local container_name=$1
    while read -r status live_time exit_time pid image_name exit_code; do
        if [ "$status" == "running" ]; then
            live_time=$(calculate_hours "$live_time")
            description="pid $pid ($image_name), uptime $live_time hours ago"
        else
            exit_time=$(calculate_hours "$exit_time")
            description="(dead)($image_name) exited $exit_time hours ago, exitcode=$exit_code"
        fi
        printf '%s\t%s\t%s\n' "$container_name" "$status" "$description"
    done< <(get_container_info "$container_name")
}

display_container_status () {
    # for container in ${matched_containers[@]}; do
    while read -r container; do
        get_container_status_description "$container"
    done < <(list_containers "$@") | \
        awk -F'\t' 'BEGIN { 
                printf "%-45s %-10s %s\n", "Service", "Status", "Description" 
            } { 
                printf "%-45s %-10s %s\n", $1, $2, $3 
            }'
}

if [ $# -eq 0 ]; then
    cat <<EOF
$0 [ container name 1 | container name 2 | container name globbing |...]
EOF
    exit 1
else
    display_container_status "$@"
fi