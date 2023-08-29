#!/usr/bin/env bash
# 用途： 安装蓝鲸的用户管理后台(usermgr/api)
# shellcheck disable=SC1091

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
USERMGR_MODULE=api

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

# 默认安装所有子模块
MODULE=usermgr
ENV_FILE=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]
            [ -s, --srcdir      [必选] "从该目录拷贝usermgr目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --log-dir         [可选] "日志目录,默认为$PREFIX/logs/usermgr" ]

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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/usermgr}
USERMGR_VERSION=$( cat "${MODULE_SRC_DIR}"/usermgr/VERSION )

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/usermgr ]]; then
    warning "$MODULE_SRC_DIR/usermgr 不存在"
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


id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; } 

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env 
install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"
install -o blueking -g blueking -m 755 -d "$PREFIX/public/$MODULE"

# 拷贝模块目录到$PREFIX
rsync -a --delete "${MODULE_SRC_DIR}/$MODULE/" "$PREFIX/$MODULE/"

case $USERMGR_MODULE in 
    api) 
        # 渲染配置
        "$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
                -e "$ENV_FILE" \
                "$MODULE_SRC_DIR/$MODULE"/support-files/templates/*api*
        chown blueking.blueking -R "$PREFIX/$MODULE" "$LOG_DIR"
        # 导入镜像
        docker load --quiet < "$MODULE_SRC_DIR"/$MODULE/support-files/images/bk-usermgr-"$USERMGR_VERSION".tar.gz
        if [ "$(docker ps --all --quiet --filter name=bk-usermgr-$USERMGR_MODULE)" != '' ]; then
            log "container: bk-usermgr-$USERMGR_MODULE already exists, stop and remove now" 
            docker stop bk-usermgr-"$USERMGR_MODULE"
            docker rm bk-usermgr-"$USERMGR_MODULE"
        fi
        # 加载容器资源限额模板
        if [ -f "$MODULE_SRC_DIR/$MODULE"/support-files/images/resource.tpl ]; then
            # shellcheck source=/dev/null
            source "$MODULE_SRC_DIR/$MODULE"/support-files/images/resource.tpl
            # shellcheck disable=SC1083
            MAX_MEM=$(eval echo \${"${USERMGR_MODULE}"_mem})
            # shellcheck disable=SC1083
            MAX_CPU_SHARES=$(eval echo \${"${USERMGR_MODULE}"_cpu})
        fi
        docker run --detach --network=host \
            --name bk-usermgr-"$USERMGR_MODULE" \
            --cpu-shares "${MAX_CPU_SHARES:-1024}" \
            --memory "${MAX_MEM:-512}" \
            --volume "$PREFIX"/"$MODULE":/data/bkce/"$MODULE" \
            --volume "$PREFIX"/public/"$MODULE":/data/bkce/public/"$MODULE" \
            --volume "$PREFIX"/logs/"$MODULE":/data/bkce/logs/"$MODULE" \
            --volume "$PREFIX"/etc/supervisor-usermgr-api.conf:/data/bkce/etc/supervisor-usermgr-api.conf \
            bk-usermgr-"$USERMGR_MODULE":"$USERMGR_VERSION"
        ;;
esac