#!/usr/bin/env bash
# 用途： 安装蓝鲸的故障自愈后台
 
# 安全模式
set -euo pipefail 

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

# PYTHON目录
PYTHON_PATH=/opt/py27/bin/python

# 监听地址
BIND_ADDR=127.0.0.1

# hosts变量文件
BK_HOSTS_ENV=${SELF_DIR}/02-dynamic/hosts.env

# 默认安装所有子模块
MODULE="fta"
PROJECTS=(fta)
RPM_DEP=(mysql-devel gcc libevent-devel patch)

# error exit handler
err_trap_handler () {
    MYSELF="$0"
    LASTLINE="$1"
    LASTERR="$2"
    echo "${MYSELF}: line ${LASTLINE} with exit code ${LASTERR}" >&2
}
trap 'err_trap_handler ${LINENO} $?' ERR

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -e, --envfile     [必填] "以该环境变量文件渲染配置" ]
            [ -m, --module      [必选] "安装的子模块(${PROJECTS[*]})" ]
            [ -b, --bind        [可选] "监听的网卡地址,默认为127.0.0.1" ]

            [ --python-path     [可选] "指定创建virtualenv时的python二进制路径" ]

            [ -s, --srcdir      [必填] "从该目录拷贝$MODULE/project目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --log-dir         [可选] "日志目录,默认为\$PREFIX/logs/$MODULE" ]

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
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -e | --envfile )
            shift
            ENV_FILE=$1
            ;;
        -m | --module )
            shift
            FTA_MODULE=$1
            ;;
        --python-path )
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/$MODULE}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/$MODULE ]]; then
    warning "$MODULE_SRC_DIR/$MODULE 不存在"
fi
if ! [[ $("$PYTHON_PATH" --version 2>&1) = *Python* ]]; then
    warning "$PYTHON_PATH 不是一个合法的python二进制"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if [[ -z "$FTA_MODULE" ]]; then
    warning "-m can't be empty"
elif ! [[ -d $MODULE_SRC_DIR/$MODULE/$FTA_MODULE ]]; then
    warning "$MODULE_SRC_DIR/$MODULE/$FTA_MODULE 不存在"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 主要是beanstalk需要是ip列表，不能用域名，需要引入ip
if ! [[ -s "$BK_HOSTS_ENV" ]]; then
    echo "$BK_HOSTS_ENV is empty"
    exit 1
else
    . "$BK_HOSTS_ENV"
fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    useradd -m -d /home/blueking -c "BlueKing EE User" --shell /bin/bash blueking 

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env 
install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"
install -o blueking -g blueking -m 755 -d /var/run/fta

# 配置/var/run临时目录重启后继续生效
cat > /etc/tmpfiles.d/fta.conf <<EOF
D /var/run/fta 0755 blueking blueking
EOF

# 拷贝模块目录到$PREFIX
rsync -a --delete "${MODULE_SRC_DIR}/$MODULE/" "$PREFIX/$MODULE/"

case $FTA_MODULE in 
    fta) 
        # 安装rpm依赖包，如果不存在
        if ! rpm -q "${RPM_DEP[@]}" >/dev/null; then
            yum -y install "${RPM_DEP[@]}"
        fi
        # 安装虚拟环境和依赖包
        "${SELF_DIR}"/install_py_venv_pkgs.sh -n "${MODULE}-${FTA_MODULE}" \
            -p "${PYTHON_PATH}" \
            -w "${PREFIX}/.envs" -a "$PREFIX/$MODULE/${FTA_MODULE}" \
            -r "$PREFIX/$MODULE/${FTA_MODULE}/requirements.txt" \
            -s "${MODULE_SRC_DIR}/$MODULE/support-files/pkgs"
        # 渲染配置
        "$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
            -e "$ENV_FILE" -E LAN_IP="$BIND_ADDR" -E BK_BEANSTALK_IP_COMMA="$BK_BEANSTALK_IP_COMMA" \
            "$MODULE_SRC_DIR"/$MODULE/support-files/templates/*
        # 生成service定义
        cat > /usr/lib/systemd/system/bk-fta.service <<EOF
[Unit]
Description=Blueking FTA Backend Supervisor daemon
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
Type=forking
EnvironmentFile=/etc/blueking/env/local.env
ExecStart=/opt/py36/bin/supervisord -c $PREFIX/etc/supervisor-fta-fta.conf
ExecStop=/opt/py36/bin/supervisorctl -c $PREFIX/etc/supervisor-fta-fta.conf shutdown
ExecReload=/opt/py36/bin/supervisorctl -c $PREFIX/etc/supervisor-fta-fta.conf reload
Restart=on-failure
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target
EOF
        ;;
    *) usage_and_exit 1 ;;
esac

# 修改属主
chown blueking.blueking -R "$PREFIX/$MODULE"

systemctl daemon-reload

if ! systemctl is-enabled "bk-fta" &>/dev/null; then
    systemctl enable --now "bk-fta"
fi
