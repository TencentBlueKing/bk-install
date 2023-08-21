#!/usr/bin/env bash

if ! command -v docker >/dev/null; then
    echo "docker: command not found"
    exit 1
fi

all_containers=$(docker ps --all --format '{{.Names}}')
current_timestamp=$(date +%s)

list_containers () {
    local matched_containers=()
    for pattern in ${@}; do
        while IFS= read -r line; do
            matched_containers+=("$line")
        done < <(echo "$all_containers" | grep -E "$pattern")
    done
    echo ${matched_containers[@]}
}

get_container_info () {
    local container_name=$1
    docker inspect --format '{{.State.Status}} {{.State.StartedAt}} {{.State.FinishedAt}} {{.State.Pid}} {{.Config.Image}} {{.State.ExitCode}}' $container_name
}

calculate_hours () {
    local given_timestamp=$(date -d "$1" +%s)
    local current_timestamp=$(date +%s)
    local time_difference=$((current_timestamp - given_timestamp))
    local hours=$(echo "scale=1; $time_difference / 3600.0" | bc)
    printf "%.2f\n" $hours
}

get_container_status_description () {
    local container_name=$1
    local info=$(get_container_info $container_name)
    local status=$(echo $info | awk '{print $1}')
    local image_name=$(echo $info | awk '{print $5}')
    if [ "$status" == "running" ]; then
        live_time=$(calculate_hours $(echo $info | awk '{print $2}'))
        pid=$(echo $info | awk '{print $4}')
        description="pid $pid ($image_name), uptime $live_time hours ago"
    else
        exit_time=$(calculate_hours $(echo $info | awk '{print $3}'))
        exit_code=$(echo $info | awk '{print $6}')
        description="(dead)($image_name) exited $exit_time hours ago, exitcode=$exit_code"
    fi
    printf '%s\t%s\t%s\t%s\n' "$container_name" "$status" "$description"
}

display_container_status () {
    local matched_containers=$(list_containers $@)
    # 只匹配存在的容器，通配符匹配为空的不作处理，如果匹配不到任何内容，则退出
    if [ -z "$matched_containers" ]; then
        echo "No containers found matching patter"
        return 1
    fi
    for container in ${matched_containers[@]}; do
        get_container_status_description $container
    done | awk -F'\t' 'BEGIN { printf "%-45s %-10s %s\n", "Service", "Status", "Description" } { printf "%-45s %-10s %s\n", $1, $2, $3 }'
}

if [ $# -eq 0 ]; then
    cat <<EOF
$0 [ container name 1 | container name 2 | container name globbing |...]
EOF
    exit 1
else
    display_container_status $@
fi