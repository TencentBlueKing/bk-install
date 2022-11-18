#!/usr/bin/env bash
# 用途： 安装蓝鲸的日志检索后台api（python3工程）
 
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
PYTHON_PATH=/opt/py36_e/bin/python3.6

# 监听地址
BIND_ADDR=127.0.0.1

# 默认安装所有子模块
MODULE="bklog"
PROJECTS=(api grafana)
RPM_DEP=(gcc libevent-devel libffi-devel mysql-devel)

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
            BKLOG_MODULE=$1
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
if [[ -z "$BKLOG_MODULE" ]]; then
    warning "-m can't be empty"
elif ! [[ -d $MODULE_SRC_DIR/$MODULE/$BKLOG_MODULE ]]; then
    warning "$MODULE_SRC_DIR/$MODULE/$BKLOG_MODULE 不存在"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    useradd -m -d /home/blueking -c "BlueKing EE User" --shell /bin/bash blueking 

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env 
install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"
install -o blueking -g blueking -m 755 -d /var/run/bklog

# 配置/var/run临时目录重启后继续生效
cat > /etc/tmpfiles.d/bklog.conf <<EOF
D /var/run/bklog 0755 blueking blueking
EOF

# 拷贝模块目录到$PREFIX
rsync -a --delete "${MODULE_SRC_DIR}/$MODULE/" "$PREFIX/$MODULE/"

cat <<EOF > /usr/lib/systemd/system/bk-log.target
[Unit]
Description=Bk log target to allow start/stop all bk-log-*.service at once

[Install]
WantedBy=multi-user.target
EOF

# 渲染配置
"$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
    -e "$ENV_FILE" -E LAN_IP="$BIND_ADDR" \
    "$MODULE_SRC_DIR"/$MODULE/support-files/templates/*

case $BKLOG_MODULE in 
    api) 
        # 安装rpm依赖包，如果不存在
        if ! rpm -q "${RPM_DEP[@]}" >/dev/null; then
            yum -y install "${RPM_DEP[@]}"
        fi
        # 安装虚拟环境和依赖包
        "${SELF_DIR}"/install_py_venv_pkgs.sh -e -n "${MODULE}-${BKLOG_MODULE}" \
            -p "${PYTHON_PATH}" \
            -w "${PREFIX}/.envs" -a "$PREFIX/$MODULE/${BKLOG_MODULE}" \
            -r "$PREFIX/$MODULE/${BKLOG_MODULE}/requirements.txt" \
            -s "${MODULE_SRC_DIR}/$MODULE/support-files/pkgs"
        if [[ "$PYTHON_PATH" = *_e* ]]; then
            # 拷贝加密解释器 //todo
            cp -a "${PYTHON_PATH}"_e "$PREFIX/.envs/${MODULE}-${BKLOG_MODULE}/bin/python"
        fi
        # 生成service定义
        cat > /usr/lib/systemd/system/bk-log-api.service <<EOF
[Unit]
Description=Blueking Bklog API Supervisor daemon
After=network-online.target
PartOf=bk-log.target

[Service]
User=blueking
Group=blueking
Type=forking
EnvironmentFile=/etc/blueking/env/local.env
Environment=BK_FILE_PATH=$PREFIX/bklog/cert/saas_priv.txt
ExecStart=/opt/py36/bin/supervisord -c $PREFIX/etc/supervisor-bklog-api.conf
ExecStop=/opt/py36/bin/supervisorctl -c $PREFIX/etc/supervisor-bklog-api.conf shutdown
ExecReload=/opt/py36/bin/supervisorctl -c $PREFIX/etc/supervisor-bklog-api.conf reload
Restart=on-failure
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target bk-log.target
EOF
    # 修改属主
    chown blueking.blueking -R "$PREFIX/$MODULE"
    systemctl daemon-reload
    if ! systemctl is-enabled "bk-log-api" &>/dev/null; then
        systemctl enable --now "bk-log-api"
    fi
        ;;
    grafana)
        # 生成service定义配置
        cat > /usr/lib/systemd/system/bk-log-grafana.service <<EOF
[Unit]
Description="Blueking grafana"
After=network-online.target
PartOf=bk-log.target

[Service]
User=blueking
Group=blueking
WorkingDirectory=$PREFIX/$MODULE/grafana
ExecStart=$PREFIX/$MODULE/grafana/bin/grafana-server \
        --homepath ./ --config ./conf/grafana.ini cfg:default.paths.logs=$PREFIX/logs/bklog/ \
        cfg:default.paths.data=./data cfg:default.paths.plugins=./plugins
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target bk-log.target
EOF
    # 修改属主
    chown blueking.blueking -R "$PREFIX/$MODULE"
    systemctl daemon-reload
    if ! systemctl is-enabled "bk-log-grafana" &>/dev/null; then
        systemctl enable --now "bk-log-grafana"
    fi
    ;;
    *) usage_and_exit 1 ;;
esac

systemctl enable bk-log.target