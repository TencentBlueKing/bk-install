#!/usr/bin/env bash
# 用途：用于安装单节点 Redis Cluster

# 安全模式
set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
REDIS_VERSION="5.0.9"
BIND_ADDR="127.0.0.1"

# redis cluster 端口起始
PORTS=("6380" "6381" "6382")

DATA_DIR="/var/lib/redis"
LOG_DIR="/var/log/redis"
PASSWORD=
NAME=

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -n, --name        [必填] "部署的 redis_cluster 实例名称" ]
            [ -p, --port        [必填] "部署的 redis_cluster 端口号列表，多个使用英文逗号分隔" ]
            [ -a, --password    [必填] "部署的 redis_cluster 密码" ]
            [ -b, --bind        [可选] "监听的网卡地址,默认为 127.0.0.1" ]

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
        -n | --name )
            shift
            NAME=$1
            ;;
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -p | --port )
            shift
            PORTS=( $1 )
            ;;
        -a | --password )
            shift
            PASSWORD=$1
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
if [[ -z "$PASSWORD" ]]; then
    warning "未指定 redis_cluster 的密码字符串"
fi
if [[ "$PASSWORD" =~ , ]]; then
    warning "redis_cluster 的密码字符串包含非法字符(逗号)"
fi

if [[ -z ${PORTS[@]} ]];then
    error "redis cluster ports列表不能为空"
else
    for port in ${PORTS[@]}; do
        if [[ $(ss -tnl4 | awk -v addr="^${BIND_ADDR}:${port}$" '$4 ~ addr' | wc -l) -ge 1 ]]; then
            warning "${BIND_ADDR}:${port} 已经监听，请确认"
        fi
    done
fi

if ! [[ "$NAME" =~ ^[a-z] ]]; then
    warning "redis_cluster 实例的名称请用小写字符开头"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装 redis_cluster
if ! rpm -ql redis &>/dev/null; then
    log "yum install redis-${REDIS_VERSION}"
    yum -q -y install redis-${REDIS_VERSION}
fi

install -dv /etc/redis/ ${LOG_DIR} ${DATA_DIR}

# 生成 redis_cluster 配置文件
for port in ${PORTS[@]}; do
    name="$NAME-$port"
    CONF_NAME=redis_cluster.conf

    # 创建配置文件目录
    install -dv /etc/redis/"$port"
    install -m 755 -o redis -g redis -d ${DATA_DIR}/"${name}"

    cat > /etc/redis/"$port"/"${CONF_NAME}" <<EOF
daemonize no
pidfile /var/run/redis-cluster/${name}.pid
port ${port}
cluster-announce-port ${port}
cluster-announce-bus-port 1${port}
bind ${BIND_ADDR}
cluster-announce-ip ${BIND_ADDR}
timeout 360
loglevel notice
logfile ${LOG_DIR}/${name}.log
tcp-backlog 511
databases 16
dbfilename ${name}.dump.rdb
dir ${DATA_DIR}/${name}
requirepass ${PASSWORD}
masterauth ${PASSWORD}
cluster-enabled yes
cluster-node-timeout 15000
cluster-config-file nodes-$port.conf
appendonly yes
EOF


    # 生成 redis cluster systemd 托管文件
    cat <<EOF > /usr/lib/systemd/system/redis-cluster-"$port".service
[Unit]
Description=Redis Cluster
After=network-online.target
PartOf=blueking.target redis-cluster.target

[Service]
ExecStart=/usr/bin/redis-server /etc/redis/$port/$CONF_NAME
WorkingDirectory=${DATA_DIR}/${name}
KillMode=process
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=blueking.target redis-cluster.target
EOF

    chown redis.redis /etc/redis/"$port"/$CONF_NAME

    log "启动 redis-cluster-""$port"".service 实例"
    systemctl daemon-reload
    systemctl start redis-cluster-"$port".service

    log "检查 redis-cluster-$port.service 状态"
    if ! systemctl status redis-cluster-"$port".service; then
        log "请检查启动日志，使用命令：journalctl -u redis-cluster-$port.service 查看失败原因"
        log "手动修复后，使用命令：systemctl start redis-cluster-$port.service 启动并确认是否启动成功"
        log "启动成功后，使用命令：systemctl enable redis-cluster-$port.service 设置开机启动"
        exit 100
    else
        log "设置Redis实例 redis-cluster-$port.service 开机启动"
        systemctl enable redis-cluster-$port.service
    fi
done

cat <<EOF > /usr/lib/systemd/system/redis-cluster.target
Description=Redis cluster to allow start/stop all redis-cluster-*.service at once

[Install]
WantedBy=multi-user.target redis-cluster.target
EOF

log "启动 redis-cluster.target 实例"
systemctl daemon-reload
systemctl start redis-cluster.target
systemctl enable redis-cluster.target
