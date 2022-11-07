#!/usr/bin/env bash
# install_redis_sentinel.sh ：安装，配置redis sentinel模式
# 参考：    - https://redis.io/topics/sentinel
#           - https://redis.io/topics/admin
# 用法：

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
REDIS_VERSION="5.0.9"
BIND_ADDR="127.0.0.1"
PORT=26379
PASSWORD=
SENTINEL_PASSWORD=
NAME=default
MASTER_NAME=mymaster
QUORUM=2

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -n, --name              [可选] "部署的redis_sentinel实例名称，默认为default" ]
            [ -M, --master-name       [可选] "部署的redis_sentinel集群的master-name，默认为mymaster" ]
            [ -m, --monitor           [必填] "监控的redis master地址和端口 形如ip:port" ]
            [ -p, --port              [必填] "部署的redis_sentinel端口号，默认26379" ]
            [ -q, --quorum            [可选] "redis_sentinel的quorum数，假设三节点，则填2，默认为2" ]
            [ -a, --password          [必填] "部署的redis_sentinel访问redis master/slave的密码" ]
            [ -s, --sentinel-password [选填] "部署的redis_sentinel密码" ]
            [ -b, --bind              [可选] "监听的网卡地址,默认为127.0.0.1" ]

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
        -M | --master-name )
            shift
            MASTER_NAME=$1
            ;;
        -m | --monitor )
            shift
            MASTER_HOSTS="$1"
            ;;
        -q | --quorum)
            shift
            QUORUM="$1"
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
        -s | --sentinel-password )
            shift
            SENTINEL_PASSWORD=$1
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
    warning "未指定 Redis 集群的密码字符串"
fi
if [[ -z "$SENTINEL_PASSWORD" ]]; then
    log "未指定 Redis sentinel 集群的密码字符串"
fi
if [[ "$PASSWORD" =~ , ]]; then
    warning "Redis 的密码字符串包含非法字符(逗号)"
fi
if ! [[ "$PORT" =~ [0-9]+ ]]; then # 其实要判断是否在1<port<65545之间
    warning "Redis-sentinel 的端口不是合法端口"
else
    if [[ $(ss -tnl4 | awk -v addr="^${BIND_ADDR}:${PORT}$" '$4 ~ addr' | wc -l) -ge 1 ]]; then
        warning "${BIND_ADDR}:${PORT} 已经监听，请确认"
    fi
fi
if ! [[ "$NAME" =~ ^[a-z] ]]; then 
    warning "redis-sentinel实例的名称请用小写字符开头"
fi
if [[ -z "$MASTER_HOSTS" ]]; then
    warning "-m(--monitor) 不能为空"
fi
if ! [[ $MASTER_HOSTS =~ [0-9:]+ ]]; then
    warning "-m 后必须是ip:port这样的字符串"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装redis
if ! rpm -ql redis &>/dev/null; then
    yum -q -y install redis-${REDIS_VERSION}
fi

# 生成 redis-sentinel 配置文件
CONF_NAME=sentinel-${NAME}.conf
SERVICE_NAME="redis-sentinel@$NAME"
log "生成 /etc/redis/$CONF_NAME 配置文件"

if ! [[ -z $SENTINEL_PASSWORD ]];then
    cat > /etc/redis/"${CONF_NAME}" <<EOF 
bind ${BIND_ADDR}
port ${PORT}
logfile "/var/log/redis/sentinel-${NAME}.log"
dir /tmp
requirepass "$SENTINEL_PASSWORD"

sentinel monitor $MASTER_NAME ${MASTER_HOSTS/:/ } $QUORUM
${SENTINEL_MONITOR_CONFIG}
sentinel auth-pass $MASTER_NAME $PASSWORD
sentinel down-after-milliseconds $MASTER_NAME 5000
sentinel deny-scripts-reconfig yes
EOF
else
    cat > /etc/redis/"${CONF_NAME}" <<EOF 
bind ${BIND_ADDR}
port ${PORT}
logfile "/var/log/redis/sentinel-${NAME}.log"
dir /tmp

sentinel monitor $MASTER_NAME ${MASTER_HOSTS/:/ } $QUORUM
${SENTINEL_MONITOR_CONFIG}
sentinel auth-pass $MASTER_NAME $PASSWORD
sentinel down-after-milliseconds $MASTER_NAME 5000
sentinel deny-scripts-reconfig yes
EOF
fi

chown redis.redis /etc/redis/"${CONF_NAME}"

log "启动Redis-sentinel "
systemctl start "$SERVICE_NAME"

log "检查redis-sentinel 状态"
if ! systemctl status "$SERVICE_NAME"; then
    log "请检查启动日志，使用命令：journalctl -u $SERVICE_NAME 查看失败原因"
    log "手动修复后，使用命令：systemctl start $SERVICE_NAME 启动并确认是否启动成功"
    log "启动成功后，使用命令：systemctl enable $SERVICE_NAME 设置开机启动"
    exit 100
else
    log "设置Redis Sentinel实例开机启动"
    systemctl enable "$SERVICE_NAME"
fi
