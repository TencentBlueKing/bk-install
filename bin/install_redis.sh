#!/usr/bin/env bash
# install_redis.sh ：安装，配置redis standalone，单机部署多实例
# 用法：

set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
REDIS_VERSION="5.0.9"
BIND_ADDR="127.0.0.1"
PORT=6379
DATA_DIR="/var/lib/redis"
LOG_DIR="/var/log/redis"
PASSWORD=
NAME=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -n, --name        [必填] "部署的redis实例名称" ]
            [ -p, --port        [必填] "部署的redis端口号" ]
            [ -a, --password    [必填] "部署的redis密码" ]
            [ -b, --bind        [可选] "监听的网卡地址,默认为127.0.0.1" ]

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
            PORT=$1
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
    warning "未指定 Redis 的密码字符串"
fi
if [[ "$PASSWORD" =~ , ]]; then
    warning "Redis 的密码字符串包含非法字符(逗号)"
fi
if ! [[ "$PORT" =~ [0-9]+ ]]; then # 其实要判断是否在1<port<65545之间
    warning "Redis 的端口不是字符串"
else
    if [[ $(ss -tnl4 | awk -v addr="^${BIND_ADDR}:${PORT}$" '$4 ~ addr' | wc -l) -ge 1 ]]; then
        warning "${BIND_ADDR}:${PORT} 已经监听，请确认"
    fi
fi
if ! [[ "$NAME" =~ ^[a-z] ]]; then 
    warning "redis实例的名称请用小写字符开头"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装redis
if ! rpm -ql redis &>/dev/null; then
    log "yum install redis-${REDIS_VERSION}"
    yum -q -y install redis-${REDIS_VERSION}
fi

# 检查系统内核参数
# 允许内核超量使用内存，防止低内存时无法fork的风险。
read -r ovm < /proc/sys/vm/overcommit_memory
if [[ $ovm -ne 1 ]]; then
    echo "vm.overcommit_memory=1" >> /etc/sysctl.d/redis.conf && \
    	sysctl vm.overcommit_memory=1
fi

# somaxconn 需要大于 redis的 tcp-backlog配置
read -r tcp_backlog < /proc/sys/net/core/somaxconn
if [[ $tcp_backlog -lt 512 ]]; then
    echo "net.core.somaxconn=512" >> /etc/sysctl.d/redis.conf && \
    	sysctl net.core.somaxconn=512
fi

# 生成 redis 配置文件
CONF_NAME=${NAME}.conf
log "生成 /etc/redis/$CONF_NAME 配置文件"
cat > /etc/redis/"${CONF_NAME}" <<EOF 
daemonize no
pidfile /var/run/redis/${NAME}.pid
port ${PORT}
bind ${BIND_ADDR}
timeout 360
loglevel notice
logfile ${LOG_DIR}/${NAME}.log
tcp-backlog 511
databases 16
rdbcompression yes
dbfilename ${NAME}.dump.rdb
dir ${DATA_DIR}/${NAME}
slave-serve-stale-data yes
slave-read-only yes
repl-disable-tcp-nodelay no
slave-priority 100
requirepass ${PASSWORD}
masterauth ${PASSWORD}
appendonly no
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
lua-time-limit 5000
slowlog-log-slower-than 10000
slowlog-max-len 1000
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-entries 512
list-max-ziplist-value 64
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit slave 4gb 4gb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
aof-rewrite-incremental-fsync yes
maxmemory-policy volatile-lru
EOF

chown redis.redis /etc/redis/"${CONF_NAME}"

# 创建dir目录
install -m 755 -o redis -g redis -d ${DATA_DIR}/${NAME}

log "启动Redis实例 redis@${NAME}"
systemctl start redis@"${NAME}"

log "检查redis@${NAME} 状态"
if ! systemctl status redis@"${NAME}"; then
    log "请检查启动日志，使用命令：journalctl -u redis@${NAME} 查看失败原因"
    log "手动修复后，使用命令：systemctl start redis@${NAME} 启动并确认是否启动成功"
    log "启动成功后，使用命令：systemctl enable redis@${NAME} 设置开机启动"
    exit 100
else
    log "设置Redis实例 redis@${NAME} 开机启动"
    systemctl enable redis@"${NAME}"
fi
