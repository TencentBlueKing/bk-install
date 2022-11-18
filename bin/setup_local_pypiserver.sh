#!/usr/bin/env bash
# 用途：在本机配置pypi目录，适用于离线安装python依赖包
# 参考：https://pip.pypa.io/en/stable/user_guide/#configuration

set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0
SELF_DIR=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")

# 全局默认变量
PYPI_PATH=/opt/pypi 
PYTHON_PATH=/opt/py27
BK_SRC_PATH=/data/src
CONFIG_PIP=0
AUTO_INSTALL=0
PYPI_PORT=8081
DISABLE_FALLBACK=
FALLBACK_URL="http://mirrors.tencent.com/pypi/simple/"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -l, --listen-ip       [必选]  指定pypiserver的监听ip地址 ]
            [ -d, --pypi-dir        [可选] "指定python pip包的存放路径，必须已存在，默认为/opt/pypi" ]
            [ -a, --auto-install    [可选] "是否搭建pypiserver" ]
            [ -c, --config-pip      [可选] "是否配置~/.config/pip/pip.conf" ]
            [ -P, --python-python   [可选] "指定使用的python" ]
            [ -p, --port            [可选] "pypiserver监听端口" ]
            [ -s, --src             [可选] "指定蓝鲸的安装包所在路径，默认为/data/src" ]
            [ --disable-fallback    [可选] "禁用pypiserver fallback到上游默认的pypi源" ]
            [ --fallback-url        [可选] "本地pypi找不到包时fallback的源url，默认为腾讯pypi镜像" ]
            [ -v, --version         [可选] 查看脚本版本号 ]
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
        -d | --pypi-dir )
            shift
            PYPI_PATH=$1
            ;;
        -a | --auto-install )
            AUTO_INSTALL=1
            ;;
        -c | --config-pip )
            CONFIG_PIP=1
            ;;
        -s | --src )
            shift
            BK_SRC_PATH=$1
            ;;
        --fallback-url )
            shift
            FALLBACK_URL=$1
            ;;
        --disable-fallback )
            DISABLE_FALLBACK=1 
            ;;
        -p | --port )
            shift
            PYPI_PORT=$1
            ;;
        -P | --python-path )
            shift
            PYTHON_PATH=$1
            ;;
        -l | --listen-ip )
            shift
            BIND_IP=$1
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
            usage_and_exit 2 
            ;;
    esac
    shift
done 

# 参数合法性有效性校验，这些可以使用通用函数校验。
if [[ ! -d "$BK_SRC_PATH" ]]; then
    warning "不存在 $BK_SRC_PATH 目录"
fi
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi
if [[ $AUTO_INSTALL -eq 0 && $CONFIG_PIP -eq 0 ]];then
    warning "参数错误,请求实例: ./setup_local_pypiserver.sh -l \$LAN_IP -a -c -s \$PKG_SRC_PATH"
fi

## 如果存在-a 安装pypiserver 并使用systemd托管
if [[ $AUTO_INSTALL -eq 1 ]]; then
    if [[ -z "$BIND_IP" ]]; then
        warning "必须指定监听IP地址，尽量使用内网ip"
    fi
    if [[ ! -f ${PYPI_PATH}/pypiserver-1.3.2-py2.py3-none-any.whl ]]; then
        warning "${PYPI_PATH}/不存在pypiserver的包，请确认解压了pip离线包到该路径"
    fi

    # 拷贝所有pkgs到$PYPI_PATH
    shopt -s nullglob
    for pkgs in "$BK_SRC_PATH"/*/support-files/pkgs; do
        log "同步 $pkgs/下的包到 $PYPI_PATH"
        rsync -a "$pkgs/" "$PYPI_PATH/"
    done
    shopt -u nullglob

    log "安装pypiserver"
    ${PYTHON_PATH}/bin/pip install --no-cache-dir --no-index --find-links "$PYPI_PATH/" pypiserver==1.3.2
    svc_unit=/etc/systemd/system/pypiserver.service
    pypi_opts=( --log-file /dev/null -p "$PYPI_PORT")
    if [[ -n "$DISABLE_FALLBACK" ]]; then
        pypi_opts+=(--disable-fallback)
    fi
    if [[ -n "$FALLBACK_URL" ]]; then
        pypi_opts+=(--fallback-url "$FALLBACK_URL")
    fi

    log "写入systemd配置文件: $svc_unit"
    cat <<EOF > "${svc_unit}"
[Unit]
Description=A minimal PyPI server for use with pip/easy_install.
After=network.target

[Service]
Type=simple
# systemd requires absolute path here too.
PIDFile=/var/run/pypiserver.pid
User=blueking
Group=blueking

ExecStart=${PYTHON_PATH}/bin/pypi-server ${pypi_opts[@]} $PYPI_PATH
ExecStop=/bin/kill -TERM \$MAINPID
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

WorkingDirectory=${PYPI_PATH}
TimeoutStartSec=3
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    log "重新加载systemd管理器配置"
    systemctl daemon-reload

    log "启动pypiserver,并设为开机启动"
    systemctl enable --now pypiserver.service 

    # 注册到consul，如果使用了
    if pgrep -x consul &>/dev/null; then
        "$SELF_DIR/reg_consul_svc" -n "pypi" -p "$PYPI_PORT" -a "$BIND_IP" 
    fi
fi

## -c  确认写入本地pip配置
if [[ $CONFIG_PIP -eq 1 ]]; then
    pip_conf=$HOME/.config/pip/pip.conf 
    if ! [[ -d ${pip_conf%/*} ]]; then
        log "创建：${pip_conf%/*} 目录"
        mkdir -p "${pip_conf%/*}"
    fi
    log "写入pip配置文件：$pip_conf"
    cat <<EOF > "$pip_conf"
[global]
timeout = 10
index-url = http://pypi.service.consul:$PYPI_PORT/simple
trusted-host = pypi.service.consul
no-cache-dir = false
EOF
fi