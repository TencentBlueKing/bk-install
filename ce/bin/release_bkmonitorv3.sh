#!/usr/bin/env bash
# 用途：更新蓝鲸监控后台

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
declare -A PROJECTS_DIR=(
    ["bk-monitor"]=monitor
    ["bk-transfer"]=transfer
    ["bk-influxdb-proxy"]=influxdb-proxy
    ["bk-grafana"]=grafana
    ["bk-unify-query"]=unify-query
    ["bk-argus-api"]=argus
    ["bk-argus-compact"]=argus
    ["bk-argus-receive"]=argus
    ["bk-argus-storegw"]=argus
    ["bk-ingester"]=ingester
)
MODULE=bkmonitorv3
MONITOR_MODULE=all
# 模块安装后所在的上一级目录
PREFIX=/data/bkee
# 蓝鲸产品包解压后存放的默认目录
MODULE_SRC_DIR=/data/src
# 渲染配置文件用的脚本
RENDER_TPL=${SELF_DIR}/render_tpl
# 渲染配置用的环境变量文件
ENV_FILE=${SELF_DIR}/04-final/bkmonitorv3.env
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
# 运行的模式
MONITOR_RUN_MODE=stable


usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
    通用参数：
            [ -p, --prefix          [可选] "安装的目标路径，默认为${PREFIX}" ]
            [ -m, --module          [可选] "安装的子模块(${!PROJECTS_DIR[@]}), 逗号分隔。all表示默认都会更新" ]
            [ -r, --render-file     [可选] "渲染蓝鲸配置的脚本路径。默认是$RENDER_TPL" ]
            [ -e, --env-file        [可选] "渲染配置文件时，使用该配置文件中定义的变量值来渲染" ]
            [ -M, --mode            [可选] "选择监控部署的模式：lite & stable, 默认为 $MONITOR_RUN_MODE" ]
            [ -u, --update-config   [可选] "是否更新配置文件，默认不更新。" ]
            [ -B, --backup-dir      [可选] "备份程序的目录，默认是$BACKUP_DIR" ]
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
            MONITOR_MODULE="$1"
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
        -M | --mode )
            shift
            MONITOR_RUN_MODE=$1
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
MONITOR_MODULE=${MONITOR_MODULE,,}          # to lower case
if [[ -z "$MONITOR_MODULE" ]] || ! [[ $MONITOR_MODULE =~ ^[a-z,-]+$ ]]; then 
    warning "-m, --module必须指定要更新的模块名，逗号分隔：如bk-monitor,bk-transfer"
fi
# 处理待更新的模块名
MONITOR_ENABLED_MODULE=()
readarray -t MONITOR_ENABLED_MODULE < \
    <(systemctl list-unit-files --state=enabled --type=service \
        | awk '/^bk-(transfer|influxdb-proxy|grafana|unify-query|argus-api|argus-receive|argus-storegw|argus-comact|ingester).service/ { sub(".service","",$1); print $1 }')
if (( ${#MONITOR_ENABLED_MODULE[@]} == 0 )); then 
    warning "there is no enabled bk-(transfer|influxdb-proxy|grafana|unify-query|argus-api|argus-receive|argus-storegw|argus-comact|ingester) systemd service on this host"
fi
# 兼容 monitor 模块运行在 docker 的情况，但并不一定准确
if [[ "$(grep monitorv3_monitor ${PREFIX}/.installed_module)" != '' ]]; then
    MONITOR_ENABLED_MODULE+=(bk-monitor)
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
if [[ $MONITOR_MODULE = all ]]; then
    UPDATE_MODULE=("${MONITOR_ENABLED_MODULE[@]}")
else
    IFS=, read -ra UPDATE_MODULE <<<"$MONITOR_MODULE"
    # 删除那些本机并未启用的service
    UPDATE_MODULE_CNT=${#UPDATE_MODULE[@]}
    for((i=0;i< UPDATE_MODULE_CNT;i++)); do
        if ! is_string_in_array "${UPDATE_MODULE[$i]}" "${MONITOR_ENABLED_MODULE[@]}"; then
            echo "${UPDATE_MODULE[$i]} is not enabled on this host"
            unset "UPDATE_MODULE[$i]"
        fi
    done
fi

if [[ ${#UPDATE_MODULE[@]} -eq 0 ]]; then
    echo "no module to update on this host, quit."
    exit 0
fi

# 备份老的包，并解压新的
tar -czf "$BACKUP_DIR/bkmonitorv3_$(date +%Y%m%d_%H%M).tgz" -C "$PREFIX" bkmonitorv3

if [[ $RELEASE_TYPE = tgz ]]; then
    # 创建临时目录
    TMP_DIR=$(mktemp -d /tmp/bkrelease_${MODULE}_XXXXXX)
    trap 'rm -rf $TMP_DIR' EXIT

    log "extract $TGZ_PATH to $TMP_DIR"
    tar -xf "$TGZ_PATH" -C "$TMP_DIR"/
    SRC_DIR="${TMP_DIR}/bkmonitorv3/"
else
    SRC_DIR="${MODULE_SRC_DIR}/bkmonitorv3/"
    rsync -a --delete "${MODULE_SRC_DIR}/bkmonitorv3/" "$PREFIX/bkmonitorv3/"
fi

# 更新程序文件（因为是python的包，用--delete为了删除一些pyc的缓存文件）
log "updating 公共文件 ..."
rsync -a --delete "${SRC_DIR}/support-files/" "$PREFIX/bkmonitorv3/support-files/"
rsync -a "${SRC_DIR}/projects.yaml" "${SRC_DIR}/VERSION" "$PREFIX/bkmonitorv3/"

log "updating 程序文件 ..."
for m in ${UPDATE_MODULE[@]}; do
    module_dir="${PROJECTS_DIR[$m]}"
    rsync -a --delete "${SRC_DIR}/${module_dir}/" "$PREFIX/bkmonitorv3/${module_dir}/"
done

# 渲染配置
if [[ $UPDATE_CONFIG -eq 1 ]]; then
    source /etc/blueking/env/local.env
    $RENDER_TPL -u -m "$MODULE" -p "$PREFIX" \
        -E LAN_IP="$LAN_IP" -e "$ENV_FILE" \
        "${PREFIX}"/bkmonitorv3/support-files/templates/*
else
    # 走固定配置从$PREFIX/etc下拷贝回去
    if [[ -d "$PREFIX"/etc/bkmonitorv3 ]]; then
        rsync -av "$PREFIX"/etc/bkmonitorv3/ "$PREFIX"/bkmonitorv3/
    fi
fi

chown blueking.blueking -R "${PREFIX}"/bkmonitorv3/
BKMONITORV3_VERSION=$( cat "${MODULE_SRC_DIR}"/bkmonitorv3/VERSION )
# 加载influxdb存储相关的配置
source "${SELF_DIR}"/../load_env.sh 
for m in "${UPDATE_MODULE[@]}"; do
    if [[ $m = "bk-monitor" ]]; then
        docker load --quiet < "${MODULE_SRC_DIR}"/bkmonitorv3/support-files/images/bk-monitor-"${BKMONITORV3_VERSION}".tar.gz
        if [ "$(docker ps --all --quiet --filter name=bk-monitor)" != '' ]; then
            log "container: bk-monitor already exists, stop and remove now" 
            docker stop bk-monitor
            docker rm bk-monitor
        fi
        docker run --detach --network=host \
            --name bk-monitor \
            --env  BK_INFLUXDB_BKMONITORV3_IP0="$BK_INFLUXDB_BKMONITORV3_IP0" \
            --env  BK_INFLUXDB_BKMONITORV3_IP1="$BK_INFLUXDB_BKMONITORV3_IP1" \
            --env-file "$ENV_FILE" \
            --volume "$PREFIX"/bkmonitorv3:/data/bkce/bkmonitorv3 \
            --volume "$PREFIX"/public/bkmonitorv3:/data/bkce/public/bkmonitorv3\
            --volume "$PREFIX"/logs/bkmonitorv3:/data/bkce/logs/bkmonitorv3 \
            --volume "$PREFIX"/etc/supervisor-bkmonitorv3-monitor-"$MONITOR_RUN_MODE".conf:/data/bkce/etc/supervisor-bkmonitorv3-monitor.conf \
            bk-monitor:"$BKMONITORV3_VERSION"
        
        break
    fi

    # 重启进程
    systemctl restart "$m"
done

# 检查本次更新的模块启动是否正常
running_status=()
for m in "${UPDATE_MODULE[@]}"; do
    if [[ $m = "bk-monitor" ]]; then
        running_status+=( "$(docker inspect --format '{{.State.Pid}} {{.Config.Image}} {{.State.Status}}' bk-monitor)" )
        break
    fi
    running_status+=( "$(systemctl show -p SubState,MainPID,Names "$m" | awk -F= '{print $2}'  | xargs)" )
done

printf "%s\n" "${running_status[@]}"

if [[ $(printf "%s\n" "${running_status[@]}" | grep -c running) -ne ${#UPDATE_MODULE[@]} ]]; then
    log "启动成功的进程数量少于更新的模块数量"
    exit 1
else
    log "启动成功的进程数量和更新的模块数量一致"
fi
