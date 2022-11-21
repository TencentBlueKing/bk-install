#!/usr/bin/env bash
# 用途： 安装蓝鲸的 apigateway

# 安全模式
set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
source $SELF_DIR/../functions
# 默认的绑定端口，配置文件已经写死
declare -A PORTS=(
    ["dashboard"]=6000
    ["dashboard-fe"]=6001
    ["api-support"]=6002
    ["api-support-fe"]=6003
    ["operator"]=6004
    ["apigateway"]=6006
    ["bk-esb"]=6010

)
declare -a MODULES=(${!PORTS[@]})

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

# PYTHON目录(默认用加密的解释器)
PYTHON_PATH=/opt/py36_e/bin/python3.6

MODULE=bk_apigateway

RPM_DEP=(mysql-devel)

ENV_FILE=
BIND_ADDR=127.0.0.1

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -b, --bind        [可选] "监听的网卡地址，默认为 127.0.0.1" ]
            [ -m, --module      [可选] "安装的子模块(${MODULES[*]}), 默认都会安装" ]
            [ -P, --python-path [可选] "指定创建 virtualenv 时的 python 二进制路径" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]

            [ -s, --srcdir      [必填] "从该目录拷贝 bk-apigateway/module 目录到 --prefix 指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --cert-path       [可选] "企业版证书存放目录，默认为$PREFIX/cert" ]
            [ -l, --log-dir     [可选] "日志目录,默认为$PREFIX/logs/bk_apigateway" ]

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
            APIGW_MODULE=$1
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
CERT_PATH=${CERT_PATH:-$PREFIX/cert}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/$MODULE ]]; then
    warning "$MODULE_SRC_DIR/$MODULE 不存在"
fi
if ! [[ $($PYTHON_PATH --version 2>&1) = *Python* ]]; then
    warning "$PYTHON_PATH 不是一个合法的python二进制"
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
install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"
install -o blueking -g blueking -m 755 -d "$PREFIX/public/$MODULE"

 # 安装rpm依赖包，如果不存在
 if ! rpm -q "${RPM_DEP[@]}" >/dev/null; then
     yum -y install "${RPM_DEP[@]}"
 fi

# 拷贝pip pkgs
rsync -a --delete "${MODULE_SRC_DIR}"/$MODULE/support-files "$PREFIX/$MODULE/"
# 拷贝证书
#rsync -a --delete "${MODULE_SRC_DIR}"/$MODULE/cert "$PREFIX/$MODULE/"

# 拷贝模块目录到 $PREFIX
rsync -a --delete "${MODULE_SRC_DIR}"/$MODULE/ "$PREFIX/$MODULE/"

# 渲染配置
"$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
    -E LAN_IP="$BIND_ADDR" -e "$ENV_FILE" \
    "$MODULE_SRC_DIR"/$MODULE/support-files/templates/*

chmod 755 -R "$PREFIX"/$MODULE/operator/

cat <<EOF > /etc/sysconfig/bk-apigw-"$APIGW_MODULE"
PORT=${PORTS[$APIGW_MODULE]}
EOF

case $APIGW_MODULE in
    api-support)
        # 安装虚拟环境和依赖包(使用加密解释器)
        "${SELF_DIR}"/install_py_venv_pkgs.sh -e -p "$PYTHON_PATH" \
        -n "apigw-${APIGW_MODULE}" \
        -w "${PREFIX}/.envs" -a "$PREFIX/$MODULE/${APIGW_MODULE}" \
        -s "${PREFIX}/$MODULE/support-files/pkgs" \
        -r "${PREFIX}/$MODULE/${APIGW_MODULE}/requirements.txt"

        if [[ "$PYTHON_PATH" = *_e* ]]; then
        # 拷贝加密解释器 //todo
        cp -a "${PYTHON_PATH}"_e "$PREFIX/.envs/apigw-${APIGW_MODULE}/bin/python"
        fi

        # migration
            (
                set +u +e
                export BK_FILE_PATH="$PREFIX"/$MODULE/cert/saas_priv.txt
                export BKPAAS_ENVIRONMENT="env"
                export BK_HOME=$PREFIX

                cd $PREFIX/$MODULE/$APIGW_MODULE/
                PATH=/$PREFIX/.envs/apigw-${APIGW_MODULE}/bin:$PATH \
                bash ./on_migrate

            )
            if [[ $? -ne 0 ]]; then
                fail "bk_apigw($APIGW_MODULE) migrate failed"
            fi
    ;;
    bk-esb)
        # 安装虚拟环境和依赖包(使用加密解释器)
        "${SELF_DIR}"/install_py_venv_pkgs.sh -e -p "$PYTHON_PATH" \
        -n "apigw-${APIGW_MODULE}" \
        -w "${PREFIX}/.envs" -a "$PREFIX/$MODULE/${APIGW_MODULE}" \
        -s "${PREFIX}/$MODULE/support-files/pkgs" \
        -r "${PREFIX}/$MODULE/${APIGW_MODULE}/requirements.txt"

        if [[ "$PYTHON_PATH" = *_e* ]]; then
        # 拷贝加密解释器 //todo
        cp -a "${PYTHON_PATH}"_e "$PREFIX/.envs/apigw-${APIGW_MODULE}/bin/python"
        fi

        # migration
            (
                set +u +e
                export BK_FILE_PATH="$PREFIX"/$MODULE/cert/saas_priv.txt
                export BKPAAS_ENVIRONMENT="env"
                export BK_HOME=$PREFIX

                cd $PREFIX/$MODULE/$APIGW_MODULE/
                PATH=/$PREFIX/.envs/apigw-${APIGW_MODULE}/bin:$PATH \
                bash ./on_migrate

            )

            if [[ $? -ne 0 ]]; then
                fail "bk_apigw($APIGW_MODULE) migrate failed"
            fi
    ;;
    dashboard)
        # 安装虚拟环境和依赖包(使用加密解释器)
        "${SELF_DIR}"/install_py_venv_pkgs.sh -e -p "$PYTHON_PATH" \
        -n "apigw-${APIGW_MODULE}" \
        -w "${PREFIX}/.envs" -a "$PREFIX/$MODULE/${APIGW_MODULE}" \
        -s "${PREFIX}/$MODULE/support-files/pkgs" \
        -r "${PREFIX}/$MODULE/${APIGW_MODULE}/requirements.txt"

        if [[ "$PYTHON_PATH" = *_e* ]]; then
        # 拷贝加密解释器 //todo
        cp -a "${PYTHON_PATH}"_e "$PREFIX/.envs/apigw-${APIGW_MODULE}/bin/python"
        fi

        # migration
            (
                set +u +e
                export BK_FILE_PATH="$PREFIX"/$MODULE/cert/saas_priv.txt
                export BKPAAS_ENVIRONMENT="env"
                export BK_HOME=$PREFIX

                cd $PREFIX/$MODULE/$APIGW_MODULE/
                PATH=/$PREFIX/.envs/apigw-${APIGW_MODULE}/bin:$PATH \
                bash ./on_migrate

            )

            if [[ $? -ne 0 ]]; then
                fail "bk_apigw($APIGW_MODULE) migrate failed"
            fi
    ;;
    *)
        echo "unknown $APIGW_MODULE"
        ;;
esac

cat > /usr/lib/systemd/system/bk-apigw.service <<EOF
[Unit]
Description=BlueKing API Gateway
After=network-online.target
PartOf=bk-apigw.target

[Service]
Type=forking
User=blueking
Group=blueking
Environment=BK_FILE_PATH=$PREFIX/$MODULE/cert/saas_priv.txt

Environment=BK_FILE_PATH=$PREFIX/$MODULE/cert/saas_priv.txt
ExecStart=/opt/py36/bin/supervisord -c $PREFIX/etc/supervisor-bk_apigateway.conf
ExecStop=/opt/py36/bin/supervisorctl -c $PREFIX/etc/supervisor-bk_apigateway.conf shutdown
ExecReload=/opt/py36/bin/supervisorctl -c $PREFIX/etc/supervisor-bk_apigateway.conf reload


Restart=on-failure
RestartSec=3s
KillSignal=SIGQUIT
LimitNOFILE=204800

[Install]
WantedBy=bk-apigw.target blueking.target
EOF

chown -R blueking.blueking "$PREFIX/$MODULE" "$LOG_DIR"

cat > /usr/lib/systemd/system/bk-apigw.target <<EOF
[Unit]
Description=BlueKing API Gateway target allowing to start/stop all bk-apigateway module instances at once

[Install]
WantedBy=multi-user.target blueking.target
EOF

systemctl daemon-reload
systemctl enable bk-apigw.target
if ! systemctl is-enabled "bk-apigw" &>/dev/null; then
    systemctl enable "bk-apigw"
fi

systemctl start bk-apigw.service

export BK_FILE_PATH="$PREFIX"/$MODULE/cert/saas_priv.txt
export BKPAAS_ENVIRONMENT="env"
export BK_HOME=$PREFIX

wait_ns_alive apigw-dashboard.service.consul || fail "apigw-dashboard.service.consul无法解析"

cd $PREFIX/$MODULE/$APIGW_MODULE/
PATH=/$PREFIX/.envs/apigw-${APIGW_MODULE}/bin:$PATH \
bash ./post_migrate

