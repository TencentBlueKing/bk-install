#!/usr/bin/env bash
# 用途：更新蓝鲸的paasagent

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
BIND_ADDR="127.0.0.1"
ENV_FILE=

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -e, --envfile     [必填] "以该环境变量文件渲染配置" ]
            [ -b, --bind        [可选] "监听的网卡地址,默认为127.0.0.1" ]

            [ -s, --srcdir      [必填] "从该目录拷贝paas_agent/目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --log-dir         [可选] "日志目录,默认为$PREFIX/logs/paasagent" ]

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
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        -p | --prefix )
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/paasagent}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR" ]]; then
    warning "$MODULE_SRC_DIR 不存在"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
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
rsync -a "$MODULE_SRC_DIR/paas_agent" "$PREFIX/" || error "更新模块(paasagent)失败"
chown -R blueking.blueking "$PREFIX/paas_agent"

### 生成环境变量配置文件
# 获取当前的sid和token
token=$(awk -F"'" '/^  token:/{print $2}' "$PREFIX/etc/paas_agent_config.yaml")
sid=$(awk -F"'" '/^  sid:/{print $2}' "$PREFIX/etc/paas_agent_config.yaml")
if [[ -z "$token" || -z "$sid" ]]; then
    error "获取当前配置($PREFIX/etc/paas_agent_config.yaml)中的sid和token配置失败。"
fi

"$SELF_DIR"/render_tpl -u -e "$ENV_FILE" -E LAN_IP="$BIND_ADDR" -m paas_agent -p "$PREFIX" \
    -E BK_PAASAGENT_SID="$sid" -E BK_PAASAGENT_TOKEN="$token" \
    "$MODULE_SRC_DIR/paas_agent/support-files/templates/#etc#paas_agent_config.yaml.tpl"

# 生成软连接（因为paas_agent不支持指定配置文件路径）
ln -sf "$PREFIX"/etc/paas_agent_config.yaml "$PREFIX"/paas_agent/paas_agent/etc/paas_agent_config.yaml

# 生成service文件
cat > /usr/lib/systemd/system/bk-paasagent.service <<EOF
[Unit]
Description="Blueking PaaS Agent"
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
WorkingDirectory=$PREFIX/paas_agent/paas_agent
ExecStart=$PREFIX/paas_agent/paas_agent/bin/paas_agent
KillMode=process
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target
EOF

systemctl daemon-reload
systemctl restart bk-paasagent

# 校验是否成功
sleep 3
if ! systemctl status bk-paasagent; then
    echo "启动paasagent失败， 请依次参考日志："
    echo "1. 启动的标准错误/标准输出日志：journalctl -u bk-paasagent"
    echo "2. 启动后的进程日志：$LOG_DIR/agent.log"
    exit 1
fi