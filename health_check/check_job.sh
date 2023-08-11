#!/usr/bin/env bash

# 通用脚本框架变量
PROGRAM=$(basename "$0")

# job 部署的模块
JOB_MODULE=()

# 排除的模块
EXCLUDE_JOB_MODULE=(
    job-direct
    job-gateway
)

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

MODULE=job

# JOB 运行的模式
RUN_MODE=stable

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为 $PREFIX" ]
            [ --run-mode        [可选] "选择作业平台的模式：lite & stable 默认为：$RUN_MODE"]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo "$@"
}

error () {
    echo "$@" 1>&2
    usage_and_exit 1
}

fail () {
    echo "$@" 1>&2
    exit 1
}

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do
    case "$1" in
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        --run-mode)
            shift
            RUN_MODE=$1
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        -*)
            error "不可识别的参数: $1"
            ;;
        *)
            break
            ;;
    esac
    shift
done

# 获取安装的子模块
if [[ $RUN_MODE == "lite" ]]; then
    while IFS= read -r module; do
        if [[ $module == "job-gateway" ]]; then
            module="job-gateway-management"
        fi
        JOB_MODULE+=("$module")
    done < <(yq e '.services[].name' "${PREFIX}/$MODULE/deploy_assemble.yml")
elif [[ $RUN_MODE == "stable" ]]; then
    while IFS= read -r module; do
        if [[ $module == "job-gateway" ]]; then
            module="job-gateway-management"
        fi
        JOB_MODULE+=("$module")
    done < <(yq e '.services[].name' "${PREFIX}/$MODULE/deploy.yml")
fi

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
