#!/usr/bin/env bash
# 安装，配置kafka cluster 
# 参考文档：https://kafka.apache.org/doc/current/kafkaStarted.html

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
BIND_ADDR="127.0.0.1"
SERVER_NUM=
CLIENT_PORT=9092
DATA_DIR="/var/lib/kafka"
CLUSTER_IP_LIST=
REPLICA_FACTOR=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -j, --join            [必填] "集群的服务器列表，逗号分隔，请注意保持顺序，broker.id会自动根据ip出现的顺序来生成" ]
            [ -z, --zookeeper       [必填] "kafka集群使用的zk集群，格式为：zk.host:2181/path" ]
            [ -p, --client-port     [选填] "部署的kafka client port, 默认9092" ]
            [ -b, --bind            [必填] "kafka的监听地址默认为127.0.0.1" ]
            [ -d, --data-dir        [选填] "kafka的数据日志目录存放路径" ]
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

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -j | --join )
            shift
            CLUSTER_IP_LIST=$1
            ;;
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -d | --data-dir)
            shift
            DATA_DIR=$1
            ;;
        -p | --client-port )
            shift
            CLIENT_PORT=$1
            ;;
        -z | --zookeeper )
            shift
            ZK_ADDR=$1
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

if [[ -z $CLUSTER_IP_LIST ]]; then
    warning "CLUSTER_IP_LIST(-j)不能为空"
fi
if ! command -v java &>/dev/null; then
    warning "java command not found, please install jdk first"
fi
# SERVER_NUM
read -r -a X <<< "${CLUSTER_IP_LIST//,/ }"
SERVER_NUM=${#X[@]}

if [[ -z "$ZK_ADDR" ]]; then
    warning "zk address不能为空。"
fi
if [[ $BIND_ADDR = "127.0.0.1" && $SERVER_NUM -gt 1 ]]; then
    warning "如果server_num大于1，那么bind_addr不能用默认的localhost地址"
fi
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 安装 kafka
if ! rpm -ql kafka &>/dev/null; then
    yum -q -y install kafka 
fi

# 配置目录权限
install -d -m 755 -o kafka -g kafka "$DATA_DIR"

# 生成kafka的broker id
myid=
for ((i=0; i<SERVER_NUM; i++)); do
    if [[ $BIND_ADDR = "${X[$i]}" ]]; then
        myid="$i"
    fi
done
if [[ -z "$myid" ]]; then
    error "bind ip(-b) is not include in ip list(-j), can't auto-generate myid"
fi

if [[ $SERVER_NUM -eq 1 ]]; then
    REPLICA_FACTOR=1
else
    REPLICA_FACTOR=2
fi

# 生成kafka配置
log "生成默认的kafka主配置文件 /etc/kafka/server.properties"

# 生成主配置
cat <<EOF > /etc/kafka/server.properties
broker.id=${myid}
listeners=PLAINTEXT://${BIND_ADDR}:${CLIENT_PORT}
port=${CLIENT_PORT}
log.dirs=${DATA_DIR}
num.network.threads=4
num.io.threads=4
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
num.partitions=1
default.replication.factor=${REPLICA_FACTOR}
num.recovery.threads.per.data.dir=1
log.retention.hours=72
log.retention.bytes=21474836480
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=$ZK_ADDR
zookeeper.connection.timeout.ms=6000
message.max.bytes=10485760
replica.fetch.max.bytes=10485760
delete.topic.enable=true
EOF

log "设置kafka开机启动"
systemctl enable kafka
# --no-block可以防止bootstrap阶段选举集群时启动卡住
systemctl --no-block start kafka