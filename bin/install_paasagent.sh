#!/usr/bin/env bash
# 用途：安装和更新蓝鲸的paasagent

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

# 运行模式（正式环境/测试环境）
MODE=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -e, --envfile     [必填] "以该环境变量文件渲染配置" ]
            [ -b, --bind        [可选] "监听的网卡地址,默认为127.0.0.1" ]
            [ -m, --mode        [必选] "正式环境(prod)，测试环境(test)" ]

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
        -m | --mode )
            shift
            MODE=$1
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
if ! [[ $MODE = prod || $MODE = test ]]; then
    warning "-m --mode必须为prod或者test"
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
rsync -a "$MODULE_SRC_DIR/paas_agent" "$PREFIX/" || error "安装模块(paasagent)失败"
rsync -a "$MODULE_SRC_DIR/cert" "$PREFIX/" || error "拷贝证书目录失败"

# apps目录是saas运行目录(不太合理，应该放到程序目录之外)
install -o blueking -g blueking -m 755 -d "$PREFIX"/paas_agent/apps 
install -o blueking -g blueking -m 755 -d "$PREFIX"/public/paas_agent
install -d -o blueking -g blueking "$PREFIX"/public/paas_agent/share

chown -R blueking.blueking "$PREFIX/paas_agent"

### 生成环境变量配置文件
# 获取sid和token
source "$ENV_FILE"  # 加载3个变量: BK_PAAS_PRIVATE_ADDR BK_PAASAGENT_SERVER_PORT BK_PAASAGENT_NGINX_PROXY_PORT
log "注册paas_agent($BIND_ADDR:$BK_PAASAGENT_SERVER_PORT,Nginx:$BK_PAASAGENT_NGINX_PROXY_PORT)到paas(appengine)"
resp=$(curl --connect-timeout 10 -s -H 'Content-Type:application/x-www-form-urlencoded' \
    -X POST -d "agent_ip=$BIND_ADDR&mode=$MODE&agent_port=$BK_PAASAGENT_SERVER_PORT&web_port=$BK_PAASAGENT_NGINX_PROXY_PORT" \
    "http://$BK_PAAS_PRIVATE_ADDR/v1/agent/init/")
token=$(jq -r .token <<<"$resp" 2>/dev/null)
sid=$(jq -r .sid <<<"$resp" 2>/dev/null)
if [[ -z "$token" || -z "$sid" ]]; then
    error "调用接口获取sid和token失败，返回信息为：$resp"
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
if ! systemctl is-enabled "bk-paasagent" &>/dev/null; then
    systemctl enable --now bk-paasagent
else
    systemctl start bk-paasagent
fi

# 校验是否成功
sleep 3
if ! systemctl status bk-paasagent; then
    echo "启动paasagent($MODE)失败， 请依次参考日志："
    echo "1. 启动的标准错误/标准输出日志：journalctl -u bk-paasagent"
    echo "2. 启动后的进程日志：$LOG_DIR/agent.log"
    exit 1
fi

# 校验healthz
code=$(curl -s -o /dev/null -w "%{http_code}" http://$BIND_ADDR:$BK_PAASAGENT_SERVER_PORT/healthz )
if [[ $code != 200 ]]; then
    echo "paasagent($MODE)启动失败，健康检查接口(http://$BIND_ADDR:$BK_PAASAGENT_SERVER_PORT/healthz)报错" >&2
    exit 1
fi

# 激活
resp=$(curl -s "http://$BK_PAAS_PRIVATE_ADDR/v1/agent/init/?agent_ip=$BIND_ADDR")
if [[ $(jq -r .agent_ip <<<"$resp" ) = "$BIND_ADDR" ]]; then
    log "激活paasagent($MODE): $BIND_ADDR:$BK_PAASAGENT_SERVER_PORT 成功"
else
    echo "激活paasagent($MODE): $BIND_ADDR:$BK_PAASAGENT_SERVER_PORT 失败 [$resp]" >&2
    exit 2
fi