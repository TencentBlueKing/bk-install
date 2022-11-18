#!/usr/bin/env bash
# 用途：安装和更新蓝鲸的$NAME，蓝鲸内部机密信息的管理和使用 
# 用法示例: bash /data/install/install_bksecrete.sh -b 10.0.5.xxx -v 10.0.5.xxx

set -euo pipefail

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
BIND_ADDR="127.0.0.1"
PORT=8400
METRIC_PORT=8401
VAULT_ADDR="127.0.0.1"
VAULT_PORT="8200"
NAME="bksecrets"

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -p, --port        [可选] "部署的$NAME监听端口号" ]
            [ -P, --metric-port [可选] "部署的$NAME metric 监听端口号]
            [ -b, --bind        [可选] "监听的网卡地址,默认为127.0.0.1" ]
            [ -v, --vault-addr  [可选] "vault地址,默认为127.0.0.1" ]
            [ -V, --vault-port  [可选] "vault监听的网卡地址,默认为8200"]
            [ -s, --srcdir      [可选] "从该目录拷贝$NAME目录到--prefix指定的目录" ]
            [ --prefix          [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --log-dir         [可选] "日志目录,默认为$PREFIX/logs/$NAME" ]

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
        -v | --vault-addr) 
            shift
            VAULT_ADDR=$1
            ;;
        -V | --vault-port) 
            shift
            VAULT_PORT=$1
            ;;
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -p | --port)
            shift
            PORT=$1
            ;;
        -P | --metric-port )
            shift
            METRIC_PORT=$1
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        --prefix )
            shift
            PREFIX=$1
            ;;
        --log-dir )
            shift
            LOG_DIR=$1
            ;; 
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --version )
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/$NAME}
CONFIG_FILE="$PREFIX/etc/$NAME.json"

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR" ]]; then
    warning "$MODULE_SRC_DIR 不存在"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    useradd -m -d /home/blueking -c "BlueKing EE User" --shell /bin/bash blueking 

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env 


# 拷贝模块目录到$PREFIX
rsync -a "$MODULE_SRC_DIR/$NAME" "$PREFIX/" || error "安装模块($NAME)失败"
chown -R blueking.blueking "$PREFIX/$NAME"

# 生成环境变量配置文件
cat >"${CONFIG_FILE}" << EOF
{
  "address": "${BIND_ADDR}",
  "port": ${PORT},
  "metric_port": ${METRIC_PORT},
  "local_ip": "${BIND_ADDR}",
  "vault_endpoints": "http://${VAULT_ADDR}:${VAULT_PORT}",
  "logs": "${LOG_DIR}",
  "pid_dir": "/var/run/$NAME"
}
EOF

# 生成service文件
cat > /usr/lib/systemd/system/bk-secrets.service <<EOF
[Unit]
Description="Blueking Secrets Server"
After=network-online.target
PartOf=blueking.target


[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/$NAME/bk-secrets-server -f $PREFIX/etc/$NAME.json
WorkingDirectory=/data/bkee/bksecrets
PIDFile=/var/run/bksecrets/bk-secrets-server.pid

KillMode=process
Restart=always
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bk-secrets
