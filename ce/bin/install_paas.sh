#!/usr/bin/env bash
# 用途： 安装蓝鲸的PaaS平台后台
# shellcheck disable=SC1091,SC2034

# 安全模式
set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
# 默认的绑定端口，配置文件已经写死
declare -A PORTS=(
    ["paas"]=8001
    ["appengine"]=8000
    ["esb"]=8002
    ["login"]=8003
    ["console"]=8004
    ["apigw"]=8005
)
# shellcheck disable=SC2206
declare -a MODULES=(${!PORTS[@]})

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src
MODULE=open_paas

ENV_FILE=
BIND_ADDR=127.0.0.1

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -b, --bind        [可选] "监听的网卡地址，默认为127.0.0.1" ]
            [ -m, --module      [可选] "安装的子模块(${MODULES[*]}), 默认都会安装" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]

            [ -s, --srcdir      [必填] "从该目录拷贝open_paas/module目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --cert-path       [可选] "证书存放目录，默认为$PREFIX/cert" ]
            [ -l, --log-dir     [可选] "日志目录,默认为$PREFIX/logs/open_paas" ]
            
            [ -v, --version     [可选] 查看脚本版本号 ]
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

version () {
    echo "$PROGRAM version $VERSION"
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do
    case "$1" in
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -m | --module )
            shift
            PAAS_MODULE=$1
            ;;
        -e | --env-file)
            shift
            ENV_FILE="$1"
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -l | --log-dir )
            shift
            LOG_DIR=$1
            ;;
        --cert-path)
            shift
            CERT_PATH=$1
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
    shift
done

LOG_DIR=${LOG_DIR:-$PREFIX/logs/open_paas}
CERT_PATH=${CERT_PATH:-$PREFIX/cert}
PAAS_VERSION=$( cat "${MODULE_SRC_DIR}"/open_paas/VERSION )

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/open_paas ]]; then
    warning "$MODULE_SRC_DIR/open_paas 不存在"
fi
if ! command -v docker >/dev/null; then
    warning "docker: command not found"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; }

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env
install -o blueking -g blueking -m 755 -d "$PREFIX/open_paas"
install -o blueking -g blueking -m 755 -d "$PREFIX/public/open_paas"

# 拷贝证书
if [ -f "${MODULE_SRC_DIR}"/open_paas/cert ]; then
    rsync -a --delete "${MODULE_SRC_DIR}"/open_paas/cert "$PREFIX/open_paas/"
fi

# 拷贝模块目录到$PREFIX，并创建虚拟环境，media目录是一个特例，它会有用户上传的saas包
rsync -a --delete --exclude=media "${MODULE_SRC_DIR}"/open_paas/"${PAAS_MODULE}"/ "$PREFIX/open_paas/${PAAS_MODULE}/"
if [[ ${PAAS_MODULE} = paas ]]; then
    rsync -a "${MODULE_SRC_DIR}/open_paas/paas/" "$PREFIX/open_paas/paas/"
fi
chown -R blueking.blueking "$PREFIX/open_paas" "$LOG_DIR"

case $PAAS_MODULE in
    login|console|esb|paas|apigw|appengine)
        # 渲染配置
        "$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
            -E LAN_IP="$BIND_ADDR" -e "$ENV_FILE" \
            "$MODULE_SRC_DIR"/$MODULE/support-files/templates/*"${PAAS_MODULE}"*
        # 导入镜像
        docker load --quiet < "${MODULE_SRC_DIR}"/open_paas/support-files/images/bk-paas-"${PAAS_VERSION}".tar.gz
        if [ "$(docker ps --all --quiet --filter name=bk-paas-"${PAAS_MODULE}")" != '' ]; then
            log "container: bk-paas-${PAAS_MODULE} already exists, stop and remove now" 
            docker stop bk-paas-"${PAAS_MODULE}"
            docker rm bk-paas-"${PAAS_MODULE}"
        fi
        # 加载容器资源限额模板
        if [ -f "${MODULE_SRC_DIR}"/open_paas/support-files/images/resource.tpl ]; then
            source "${MODULE_SRC_DIR}"/open_paas/support-files/images/resource.tpl
            # shellcheck disable=SC1083
            MAX_MEM=$(eval echo \${"${PAAS_MODULE}"_mem})
            # shellcheck disable=SC1083
            MAX_CPU_SHARES=$(eval echo \${"${PAAS_MODULE}"_cpu})
        fi
        docker run --detach --network=host \
            --name bk-paas-"$PAAS_MODULE" \
            --cpu-shares "${MAX_CPU_SHARES:-1024}" \
            --memory "${MAX_MEM:-512}" \
            --volume "$PREFIX"/open_paas:/data/bkce/open_paas \
            --volume "$CERT_PATH":/data/bkce/cert \
            --volume "$PREFIX"/public/open_paas:/data/bkce/public/open_paas \
            --volume "$PREFIX"/logs/open_paas:/data/bkce/logs/open_paas \
            --volume "$PREFIX"/etc/uwsgi-open_paas-"$PAAS_MODULE".ini:/data/bkce/etc/uwsgi-open_paas-"$PAAS_MODULE".ini \
            bk-paas-"$PAAS_MODULE":"$PAAS_VERSION"
        ;;
    *)
        echo "unknown $PAAS_MODULE"
        exit 1
        ;;
esac