#!/usr/bin/env bash

JOB_MODULE=(
    job-backup
    job-config
    job-crontab
    job-execute
    job-gateway-management
    job-logsvr
    job-manage
    job-analysis
)

EXCLUDE_JOB_MODULE=(
    job-direct
    job-gateway
)

TRUE="\e[1;32mtrue\e[0m"
FALSE="\e[1;31mfalse\e[0m"
# get registerd JOB service 
CONSUL_JOB_SVC=( $(curl -s http://127.0.0.1:8500/v1/catalog/services | jq -r 'keys[]' | grep -E '^job-\w+(-\w+)?$' | grep -vxFf <(printf "%s\n" "${EXCLUDE_JOB_MODULE[@]}")) )

if [[ ${#CONSUL_JOB_SVC[@]} -lt ${#JOB_MODULE[@]} ]]; then
    printf "%s" "注册到consul上的job服务仅有："
    printf "%s," "${CONSUL_JOB_SVC[@]}"
    printf "\n"
    exit 1
fi

declare -A HEALTH=()
for m in "${JOB_MODULE[@]}"; do
    health_url=$(dig "${m}".service.consul srv +short | awk '{print "http://" $4 ":" $3 "/actuator/health" }' | head -1)
    IFS=$'\n' read -r -d "" resp code < <(curl -s -w "\n%{http_code}\n" --connect-timeout 2 "$health_url")
    if [[ $(jq -r .status <<<"$resp") = "UP" ]]; then
        HEALTH[$m]="$TRUE"
    else
        HEALTH[$m]="$FALSE"
        HEALTH_MSG[$m]="$resp"
    fi
done

for m in "${!HEALTH[@]}"; do
    printf "%-15s: %-7b" "$m" "${HEALTH[$m]}"
    if [[ -n "${HEALTH_MSG[$m]}" ]]; then
        printf " Reason: %s\n" "$(jq -r -c <<<"${HEALTH_MSG[$m]}")"
    else
        printf "\n"
    fi
done
