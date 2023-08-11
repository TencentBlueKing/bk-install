#!/usr/bin/env bash
# 用途：更新蓝鲸的作业平台后台

# 安全模式
set -euo pipefail 

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")

# job 的模块
PROJECTS=()

MODULE=job
JOB_MODULE=all
# 模块安装后所在的上一级目录
PREFIX=/data/bkee
# 蓝鲸产品包解压后存放的默认目录
MODULE_SRC_DIR=/data/src
# 渲染配置文件用的脚本
RENDER_TPL=${SELF_DIR}/render_tpl
# 渲染配置用的环境变量文件
ENV_FILE=${SELF_DIR}/04-final/job.env 
# 如果使用tgz来更新，则从该目录来找tgz文件
RELEASE_DIR=/data/release
# 如果使用tgz来更新，该文件的文件名
TGZ_NAME=
# 备份目录
BACKUP_DIR=/data/src/backup
# 是否需要render配置文件
UPDATE_CONFIG=
# 更新模式（tgz|src）
RELEASE_TYPE=
# 需要更新的模块列表
UPDATE_MODULE=()

# 运行模式
RUN_MODE=stable

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
    通用参数：
            [ -p, --prefix          [可选] "安装的目标路径，默认为${PREFIX}" ]
            [ -m, --module          [可选] "安装的子模块, 逗号分隔。ALL表示默认都会更新" ]
            [ -r, --render-file     [可选] "渲染蓝鲸配置的脚本路径。默认是$RENDER_TPL" ]
            [ -e, --env-file        [可选] "渲染配置文件时，使用该配置文件中定义的变量值来渲染" ]
            [ -u, --update-config   [可选] "是否更新配置文件，默认不更新。" ]
            [ -B, --backup-dir      [可选] "备份程序的目录，默认是$BACKUP_DIR" ]
            [ --run-mode            [可选] "选择作业平台的模式：lite & stable 默认为：$RUN_MODE"]
            [ -v, --version         [可选] "脚本版本号" ]

    更新模式有两种:
    1. 使用tgz包更新，则需要指定以下参数：
            [ -d, --release-dir     [可选] "$MODULE安装包存放目录，默认是$RELEASE_DIR" ]
            [ -f, --filename        [必选] "安装包名，不带路径" ]
    
    2. 使用中控机解压后的$MODULE_SRC_DIR/{module} 来更新: 需要指定以下参数
            [ -s, --srcdir      [可选] "从该目录拷贝$MODULE/目录到--prefix指定的目录" ]
    
    如果以上三个参数都指定了，会以tgz包的参数优先使用，忽略-s指定的目录
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

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

version () {
    echo "$PROGRAM version $VERSION"
}
# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -m | --module )
            shift
            JOB_MODULE="$1"
            ;;
        -e | --env-file )
            shift
            ENV_FILE="$1"
            ;;
        -r | --render-file )
            shift
            RENDER_TPL=$1
            ;;
        -u | --update-config )
            UPDATE_CONFIG=1
            ;;
        -B | --backup-dir)
            shift
            BACKUP_DIR=$1
            ;;
        -d | --release-dir)
            shift
            RELEASE_DIR=$1
            ;;
        -f | --filename)
            shift
            TGZ_NAME=$1
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        --run-mode)
            shift
            RUN_MODE=$1
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --version | -v | -V )
            version 
            exit 0
            ;;
        -*)
            error "不可识别的参数: $1"
            ;;
        *) 
            break
            ;;
    esac
    shift $(($# == 0 ? 0 : 1))
done 

check_exists () {
    local file=$1
    if ! [[ -e "$file" ]]; then
        warning "$file is not exists. please check"
    fi
}

is_string_in_array() {
    local e
    for e in "${@:2}"; do
        [[ "$e" == "$1" ]] && return 0
    done
    return 1
}

# 首先需要确定是哪种模式更新
if [[ -n "$TGZ_NAME" ]]; then
    # 如果确定 $TGZ_NAME 变量，那么无论如何都优先用tgz包模式更新
    RELEASE_TYPE=tgz
    TGZ_NAME=${TGZ_NAME##*/}    # 兼容传入带前缀路径的包名
    TGZ_PATH=${RELEASE_DIR}/$TGZ_NAME
else
    RELEASE_TYPE=src
fi

# 判断传入的module是否符合预期
JOB_MODULE=${JOB_MODULE,,}          # to lower case
if [[ -z $JOB_MODULE ]] || ! [[ $JOB_MODULE =~ ^[a-z,-]+$ ]]; then
    warning "-m, --module必须指定要更新的模块名, 逗号分隔: 如bk-job-config,bk-job-logsvr"
fi
# 处理待更新的模块名
JOB_ENABLED_MODULE=()
readarray -t JOB_ENABLED_MODULE < \
    <(systemctl list-unit-files --state=enabled --type=service \
        | awk '/^bk-job-[a-z-]+\.service/ { sub(".service","",$1); print $1 }')

if (( ${#JOB_ENABLED_MODULE[@]} == 0 )); then 
    warning "there is no enabled bk-job-* systemd service on this host"
fi
### 文件/文件夹是否存在判断
# 通用的变量
for f in "$PREFIX" "$BACKUP_DIR"; do 
    check_exists "$f"
done
if [[ $UPDATE_CONFIG -eq 1 ]]; then 
    for f in "$RENDER_TPL" "$ENV_FILE"; do
        check_exists "$f"
    done
fi
# 不同release模式的差异判断
if [[ $RELEASE_TYPE = tgz ]]; then 
    check_exists "$TGZ_PATH"
else
    check_exists "$MODULE_SRC_DIR"/$MODULE 
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 解析需要更新的模块，如果是all，则包含所有模块
if [[ $JOB_MODULE = all ]]; then
    UPDATE_MODULE=("${JOB_ENABLED_MODULE[@]}")
else
    IFS=, read -ra UPDATE_MODULE <<<"$JOB_MODULE"
    # 删除那些本机并未启用的service
    UPDATE_MODULE_CNT=${#UPDATE_MODULE[@]}
    for((i=0;i< UPDATE_MODULE_CNT;i++)); do
        if ! is_string_in_array "${UPDATE_MODULE[$i]}" "${JOB_ENABLED_MODULE[@]}"; then
            echo "${UPDATE_MODULE[$i]} is not enabled on this host"
            unset "UPDATE_MODULE[$i]"
        fi
    done
fi

if [[ ${#UPDATE_MODULE[@]} -eq 0 ]]; then
    echo "no module to update on this host, quit."
    exit 0
fi

# 备份现网目录
tar -C "$PREFIX" -czf "$BACKUP_DIR/job_backend-$(date +%Y%m%d_%H%M).tgz"  job/backend etc/job

# 更新文件
if [[ $RELEASE_TYPE = tgz ]]; then
    # 创建临时目录
    TMP_DIR=$(mktemp -d /tmp/bkrelease_${MODULE}_XXXXXX)
    trap 'rm -rf $TMP_DIR' EXIT

    log "extract $TGZ_PATH to $TMP_DIR"
    tar -xf "$TGZ_PATH" -C "$TMP_DIR"/

    # 更新全局文件
    log "updating 全局文件 ..."
    rsync --delete -av "${TMP_DIR}"/job/ "$PREFIX"/job/
else
    rsync --delete -av "${MODULE_SRC_DIR}/job/" "$PREFIX"/job/
fi

# 渲染配置文件
if [[ $UPDATE_CONFIG = 1 ]]; then
    $RENDER_TPL -u -p "$PREFIX" -m job -e "$ENV_FILE" "$PREFIX/job/support-files/templates"/*
fi

chown blueking.blueking -R "$PREFIX"/job "$PREFIX"/etc/job

if [[ $RUN_MODE == "stable" ]]; then
    # 更新 bk-job-config 如果本机有启用
    if is_string_in_array "bk-job-config" "${UPDATE_MODULE[@]}"; then
        log "restarting bk-job-config first"
        systemctl restart bk-job-config
    fi

    # 需要验证job-config是否healthy
    counter=30
    log "waiting for job-config healthy"
    until getent hosts job-config.service.consul &>/dev/null || [[ $counter -eq 0 ]]; do
        sleep 1
        ((counter--))
    done
    [[ $counter -eq 0 ]] && { log "job-config启动失败，15s内未注册成功, 中止。"; exit 1;}

    if ! curl -s http://job-config.service.consul:10500/actuator/health | grep -q UP &>/dev/null; then
        log "job-config状态不健康，中止操作。"
    fi
fi

for m in "${UPDATE_MODULE[@]}"; do
    if [[ $m = "bk-job-config" ]];then
        log "skip $m"
    else
        log "starting $m"
        systemctl restart "$m"
        echo
    fi
done

# 检查本次更新的模块启动是否正常
running_status=()
for m in "${UPDATE_MODULE[@]}"; do
    running_status+=( "$(systemctl show -p SubState,MainPID,Names "$m" | awk -F= '{print $2}'  | xargs)" )
done

printf "%s\n" "${running_status[@]}"

if [[ $(printf "%s\n" "${running_status[@]}" | grep -c running) -ne ${#UPDATE_MODULE[@]} ]]; then
    log "启动成功的进程数量少于更新的模块数量"
    exit 1
else
    log "启动成功的进程数量和更新的模块数量一致"
fi
