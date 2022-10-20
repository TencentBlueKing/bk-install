#!/usr/bin/env bash
# install_consul.sh ：安装，配置consul(server/client)
# 参考文档：https://learn.hashicorp.com/consul/datacenter-deploy/deployment-guide
# 用法：

# 安全模式
set -euo pipefail 

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
BIND_ADDR="127.0.0.1"
SERVER_NUM=3
DNS_PORT=8600
HTTP_PORT=8500
DATA_DIR="/var/lib/consul"
LOG_DIR="/var/log/consul"
DATACENTER="dc"
NODE_NAME=$HOSTNAME
ROLE="client"
CLUSTER_IP_LIST=
CONSUL_VERSION="1.7.9"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -j, --join            [必填] "集群auto join的服务器列表，逗号分隔" ]
            [ -e, --encrypt-key     [必填] "集群通信的key，用consul keygen生成，集群内必须一致" ]
            [ -d, --data-center     [选填] "datacenter名字，默认为dc" ]
            [ -r, --role            [可选] "部署的consul角色，取值server或client，默认为client" ]
            [ -V, --consul-version  [可选] "部署的consul版本号" ]
            [ --dns-port            [可选] "部署的consul dns 端口号，默认为8600" ]
            [ --http-port           [可选] "部署的consul http 端口号，默认为8500" ]
            [ -b, --bind            [可选] "监听的网卡地址,默认为127.0.0.1" ]
            [ -n, --server-number   [可选] "如果是server模式，配置集群中的server数量" ]
            [ --node                [可选] "node_name，配置consul节点名，默认为hostname" ]
            [ -v, --version         [可选] "查看脚本版本号" ]
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

# error exit handler
err_trap_handler () {
    MYSELF="$0"
    LASTLINE="$1"
    LASTERR="$2"
    echo "${MYSELF}: line ${LASTLINE} with exit code ${LASTERR}" >&2
}
trap 'err_trap_handler ${LINENO} $?' ERR

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -r | --role )
            shift
            ROLE=$1
            ;;
        -j | --join )
            shift
            CLUSTER_IP_LIST=$1
            ;;
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -V | --consul-version )
            shift
            CONSUL_VERSION=$1
            ;;
        -d | --data-center )
            shift
            DATACENTER=$1
            ;;
        --dns-port )
            shift
            DNS_PORT=$1
            ;;
        --http-port )
            shift
            HTTP_PORT=$1
            ;;
        -n | --server-number )
            shift
            SERVER_NUM=$1
            ;;
        --node )
            shift
            NODE_NAME=$1
            ;;
        -e | --encrypt-key )
            shift
            ENCRYPT_KEY=$1
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

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ $SERVER_NUM -eq 1 || $SERVER_NUM -eq 3 || $SERVER_NUM -eq 5 || $SERVER_NUM -eq 7 ]]; then
    warning "consul server数量不满足要求, 建议生产环境使用3,5,7奇数台consul"
fi
if [[ -z $CLUSTER_IP_LIST ]]; then
    warning "CLUSTER_IP_LIST(-j)不能为空"
fi
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 安装 consul
if ! rpm -ql consul &>/dev/null; then
    yum -q -y install consul-"${CONSUL_VERSION}"
fi

# 生成consul配置
log "生成consul主配置文件 /etc/consul.d/consul.json"

# get nameservers to json array
Y=$(awk '/^nameserver/ { printf "%8s\042%s\042,\n", " ", $2 }' /etc/resolv.conf | grep -wv 127.0.0.1 || true)
recursors="${Y%,}"
if [[ -n "$recursors" ]]; then
    cat <<EOF > /etc/consul.d/recursors.json
{
    "recursors": [
$recursors
    ]
}
EOF
fi

cat <<EOF > /etc/consul.d/consul.json
{
    "bind_addr": "$BIND_ADDR",
    "log_level": "info",
    "log_file": "$LOG_DIR/consul.log",
    "datacenter": "$DATACENTER",
    "data_dir": "$DATA_DIR",
    "node_name": "$NODE_NAME",
    "disable_update_check": true,
    "enable_local_script_checks": true,
    "encrypt": "$ENCRYPT_KEY",
    "ports": {
        "dns": $DNS_PORT,
        "http": $HTTP_PORT
    }
}
EOF

# 生成consul server配置
if [[ $ROLE = "server" ]]; then
    log "生成server模式的配置文件: /etc/consul.d/server.json"
    cat <<EOF > /etc/consul.d/server.json
{
    "server": true,
    "bootstrap_expect": $SERVER_NUM
}
EOF

    log "生成server模式的telemetry配置文件：/etc/consul.d/telemetry.json"
    cat <<EOF > /etc/consul.d/telemetry.json
{
    "telemetry": {
        "prometheus_retention_time": "480h",
        "disable_hostname": true
    }
}
EOF
fi

# 生成consul的auto_join配置
read -r -a X <<< "${CLUSTER_IP_LIST//,/ }"
ip_json="[$(printf '"%q",' "${X[@]}")"
ip_json="${ip_json%,}]"		    # 删除最后一个逗号
cat <<EOF > /etc/consul.d/auto_join.json
{
    "retry_join": $ip_json
}
EOF

# 存放自定义的service定义
install -d /etc/consul.d/service
chown root.consul -R /etc/consul.d
chmod 640 /etc/consul.d/*.json

# 校验json是否合法，否则提示
if ! consul validate /etc/consul.d; then
    log "consul 配置文件校验失败，请根据stderr的错误提示修复" 
    exit 1
fi

log "设置consul开机启动"
systemctl enable consul
# --no-block可以防止bootstrap阶段选举集群时启动卡住
systemctl --no-block start consul

# 修改域名解析配置
log "设置 resolv.conf"
sed -i '/option/s/rotate//' /etc/resolv.conf
if ! grep -q "nameserver.*127.0.0.1" /etc/resolv.conf; then
    if [[ -s /etc/resolv.conf ]]; then
        sed -i '1i nameserver 127.0.0.1' /etc/resolv.conf
    else
        echo "nameserver 127.0.0.1" >> /etc/resolv.conf 
    fi
fi
if ! grep -q "search node.consul" /etc/resolv.conf; then
    echo "search node.consul" >> /etc/resolv.conf
fi
# 关闭nscd的服务
if systemctl is-active nscd &>/dev/null; then
    systemctl stop nscd 2>/dev/null
fi

# 检查是否生效, 直接通过dns接口检测
log "等待consul服务ready"
timeout=10
until [[ $timeout -eq 0 ]] || [[ -n $(dig +short +time=1 +tries=1 consul.service.consul) ]]; do
    sleep 1
    ((timeout--))
done
if [[ $timeout -gt 0 ]]; then
    log "部署consul成功"
else
    log "部署consul失败"
    exit 1
fi
