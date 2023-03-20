#!/usr/bin/env bash
# 用途： 安装蓝鲸的PaaS平台后台

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
declare -a MODULES=(${!PORTS[@]})

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

# PYTHON目录(默认用加密的解释器)
#PYTHON_PATH=/opt/py36_e/bin/python3.6

MODULE=open_paas

#RPM_DEP=(gcc mysql mysql-devel openssl-devel libevent-devel bzip2-devel sqlite-devel tk-devel gdbm-devel libffi-devel db4-devel libpcap-devel xz-devel pcre-devel nfs-utils mailcap)

ENV_FILE=
BIND_ADDR=127.0.0.1

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -b, --bind        [可选] "监听的网卡地址，默认为127.0.0.1" ]
            [ -m, --module      [可选] "安装的子模块(${MODULES[*]}), 默认都会安装" ]
            [ -P, --python-path [可选] "指定创建virtualenv时的python二进制路径" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]

            [ -s, --srcdir      [必填] "从该目录拷贝open_paas/module目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --cert-path       [可选] "企业版证书存放目录，默认为$PREFIX/cert" ]
            [ -l, --log-dir     [可选] "日志目录,默认为$PREFIX/logs/open_paas" ]
            [ --memory          [可选] "Memory limit" ]
            [ --cpu-shares      [可选] "CPU shares (relative weight)"]
            
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
        -P | --python-path )
            shift
            PYTHON_PATH=$1
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
        --memory)
            shift
            MAX_CANTAINER_MEM=$1
            ;;
        --cpu-shares)
            shift
            MAX_CPU_SHARES=$1
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
MAX_MEM=${MAX_CANTAINER_MEM:-1000}m
MAX_CPU_SHARES=${MAX_CANTAINER_CPU:-512}
PAAS_VERSION=$( cat "${MODULE_SRC_DIR}"/open_paas/VERSION )

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/open_paas ]]; then
    warning "$MODULE_SRC_DIR/open_paas 不存在"
fi
#if ! [[ $($PYTHON_PATH --version 2>&1) = *Python* ]]; then
#    warning "$PYTHON_PATH 不是一个合法的python二进制"
#fi
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
install -o blueking -g blueking -m 755 -d /var/run/open_paas

# 配置/var/run临时目录重启后继续生效
cat > /etc/tmpfiles.d/open_paas.conf <<EOF
D /var/run/open_paas 0755 blueking blueking
EOF

# # 安装rpm依赖包，如果不存在
# if ! rpm -q "${RPM_DEP[@]}" >/dev/null; then
#     yum -y install "${RPM_DEP[@]}"
# fi

# 拷贝pip pkgs
#rsync -a --delete --exclude=images "${MODULE_SRC_DIR}"/open_paas/support-files "$PREFIX/open_paas/"
# 拷贝证书
rsync -a --delete "${MODULE_SRC_DIR}"/open_paas/cert "$PREFIX/open_paas/"

# 拷贝模块目录到$PREFIX，并创建虚拟环境，media目录是一个特例，它会有用户上传的saas包
rsync -a --delete --exclude=media "${MODULE_SRC_DIR}"/open_paas/"${PAAS_MODULE}"/ "$PREFIX/open_paas/${PAAS_MODULE}/"
if [[ ${PAAS_MODULE} = paas ]]; then
    rsync -a "${MODULE_SRC_DIR}/open_paas/paas/" "$PREFIX/open_paas/paas/"
fi
chown -R blueking.blueking "$PREFIX/open_paas" "$LOG_DIR"

# 导入镜像
docker load < ${MODULE_SRC_DIR}/open_paas/support-files/images/bk-paas-*.tar.gz

case $PAAS_MODULE in
    login|console|esb|paas|apigw|appengine)
        # 渲染配置
        "$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
            -E LAN_IP="$BIND_ADDR" -e "$ENV_FILE" \
            "$MODULE_SRC_DIR"/$MODULE/support-files/templates/*"${PAAS_MODULE}"*

        if [ "$(docker ps -a -q --filter name=bk-paas-${PAAS_MODULE})" != '' ]; then
            docker rm -f bk-paas-${PAAS_MODULE}
        fi
        docker run --detach --network=host \
            --name bk-paas-${PAAS_MODULE} \
            --volume $PREFIX/open_paas:/data/bkce/open_paas \
            --volume $PREFIX/etc/uwsgi-open_paas-${PAAS_MODULE}.ini:/data/bkce/etc/uwsgi-open_paas-${PAAS_MODULE}.ini \
            --volume $PREFIX/etc/uwsgi-open_paas-${PAAS_MODULE}.ini:/data/bkce/etc/uwsgi-open_paas-${PAAS_MODULE}.ini \
            --volume $PREFIX/logs/open_paas/${PAAS_MODULE}:/data/bkce/logs/open_paas/${PAAS_MODULE} \
            --cpu-shares ${MAX_CPU_SHARES} \
            --memory ${MAX_MEM} \
            bk-paas-${PAAS_MODULE}:${PAAS_VERSION}
        ;;
    *)
        echo "unknown $PAAS_MODULE"
        exit 1
        ;;
esac