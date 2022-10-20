#!/usr/bin/env bash
# 安装，配置zookeeper cluster 
# 参考文档：https://zookeeper.apache.org/doc/current/zookeeperStarted.html

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
BIND_ADDR="127.0.0.1"
SERVER_NUM=3
CLIENT_PORT=2181
PEER_PORT=2888
ELECTION_PORT=3888
DATA_DIR="/var/lib/zookeeper"
CLUSTER_IP_LIST=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -j, --join            [必填] "集群的服务器列表，逗号分隔" ]
            [ --client-port         [选填] "部署的zookeeper client port, 默认2181" ]
            [ --peer-port           [选填] "部署的zookeeper peer port, 默认2888" ]
            [ --election-port       [选填] "部署的zookeeper election port, 默认3888" ]
            [ -b, --bind            [必填] "zookeeper的监听地址默认为127.0.0.1" ]
            [ -d, --data-dir        [可选] "zookeeper的datadir路径，默认为/var/lib/zookeeper" ]
            [ -n, --server-number   [可选] "配置集群中的server数量" ]
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
        -d | --data )
            shift
            DATA_DIR=$1
            ;;
        --client-port )
            shift
            CLIENT_PORT=$1
            ;;
        --peer-port )
            shift
            PEER_PORT=$1
            ;;
        --election-port )
            shift
            ELECTION_PORT=$1
            ;;
        -n | --server-number )
            shift
            SERVER_NUM=$1
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
    warning "zookeeper server数量不满足要求, 建议生产环境使用3,5,7奇数台zookeeper"
fi
if [[ -z $CLUSTER_IP_LIST ]]; then
    warning "CLUSTER_IP_LIST(-j)不能为空"
fi
if ! command -v java &>/dev/null; then
    warning "java command not found, please install jdk first"
fi
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 安装 zookeeper
if ! rpm -ql zookeeper &>/dev/null; then
    yum -y install zookeeper 
fi

# 创建data_dir
install -d -m 755 -o zookeeper -g zookeeper "$DATA_DIR"

# 生成zookeeper配置
log "生成zookeeper主配置文件 /etc/zookeeper/zoo.cfg"

# 生成主配置
cat <<EOF > /etc/zookeeper/zoo.cfg
tickTime=2000
initLimit=10
syncLimit=20
dataDir=$DATA_DIR
# 建议datalogDir放到另外一块磁盘，增加性能
#dataLogDir=/disk/xxxx
clientPortAddress=$BIND_ADDR
clientPort=$CLIENT_PORT
maxClientCnxns=60
autopurge.snapRetainCount=5
autopurge.purgeInterval=8

# specify all zookeeper servers
# The fist port is used by followers to connect to the leader
# The second one is used for leader election
EOF

# 修改JMX监听本地回环地址
if [[ -f /etc/sysconfig/zookeeper ]]; then
    sed -i '/^JMXLOCALONLY/s/false/true/' /etc/sysconfig/zookeeper
fi

# 生成zookeeper的集群配置
read -r -a X <<< "${CLUSTER_IP_LIST//,/ }"
myid=
for ((i=0; i<${#X[@]}; i++)); do
    id=$((i+1))
    printf "server.%d=%s:%d:%d\n" "$id" "${X[$i]}" "$PEER_PORT" "$ELECTION_PORT" >> /etc/zookeeper/zoo.cfg
    if [[ $BIND_ADDR = "${X[$i]}" ]]; then
        myid="$id"
    fi
done
if [[ -z "$myid" ]]; then
    error "bind ip(-b) is not include in ip list(-j), can't auto-generate myid"
else
    echo -n "$myid" > "$DATA_DIR"/myid
    chown root.zookeeper "$DATA_DIR"/myid
fi

chown root.zookeeper -R /etc/zookeeper
chmod 750 /etc/zookeeper/*

log "设置zookeeper开机启动"
systemctl enable zookeeper
# --no-block可以防止bootstrap阶段选举集群时启动卡住
systemctl --no-block start zookeeper