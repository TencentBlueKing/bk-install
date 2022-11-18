#!/usr/bin/env bash
# install_es.sh ：安装,配置es,支持单实例和集群部署
# 用法： ./install_es.sh -b $IP1 -s $IP1,$IP2,$IP3 -V 7.2.0 -p 9300 -P 9200 

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
ES_VERSION="7.16.1"
BIND_ADDR="127.0.0.1"
ES_REST_PORT="9200"
ES_TRANSPORT_PORT="9300"

DATA_DIR="/var/lib/elasticsearch"
LOG_DIR="/var/log/elasticsearch"

SERVER_IP_LIST=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?             [可选] "查看帮助" ]
            [ -V, --es-version          [可选] "指定安装的ES版本，默认是'$ES_VERSION'" ]
            [ -b, --bind                [可选] "监听的网卡地址,默认为127.0.0.1" ]
            [ -s, --server-ip-list      [必填] "集群的服务器列表，逗号分隔" ]
            [ -d, --data-dir            [可选] "es数据目录,默认为/var/lib" ]
            [ -l, --log-dir             [可选] "es日志目录,默认为/var/log" ]
            [ -p, --es-transport-port   [可选] "ES_TRANSPORT_PORT,默认为9300" ]
            [ -P, --es-rest-port        [可选] "ES_REST_PORT,默认为9200"]
            [ -v, --version             [可选] "查看脚本版本号" ]
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
        -V | --es-version )
            shift
            ES_VERSION=$1
            ;;
        -d | --data-dir )
            shift
            DATA_DIR=$1
            ;;
        -l  | --log-dir )
            shift
            LOG_DIR=$1
            ;;
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -s | --server-ip-list)
            shift
            SERVER_IP_LIST=$1
            ;;
        -p | --es-transport-port )
            shift
            ES_TRANSPORT_PORT=$1
            ;;
        -P | --es-rest-port )
            shift
            ES_REST_PORT=$1
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --version | -v  )
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

# 参数合法性有效性校验，这可以使用通用函数校验。
if ! [[ "$ES_TRANSPORT_PORT" =~ [0-9]+ ]]; then # 其实要判断是否在1<port<65545之间
    error "ES_TRANSPORT 端口不是字符串"
else
    if [[ $(ss -tnl4 | awk -v addr="^${BIND_ADDR}:${ES_TRANSPORT_PORT}$" '$4 ~ addr' | wc -l) -ge 1 ]]; then
        error "${BIND_ADDR}:${ES_TRANSPORT_PORT} 已经监听，请确认"
    fi
fi
if ! [[ "$ES_REST_PORT" =~ [0-9]+ ]]; then # 其实要判断是否在1<port<65545之间
    error "ES_REST 端口不是字符串" 
else
    if [[ $(ss -tnl4 | awk -v addr="^${BIND_ADDR}:${ES_REST_PORT}$" '$4 ~ addr' | wc -l) -ge 1 ]]; then
        error "${BIND_ADDR}:${ES_REST_PORT} 已经监听，请确认"
    fi
fi

if [[ -z $SERVER_IP_LIST ]]; then
    error "SERVER_IP_LIST(-j)不能为空"
fi
read -r -a X <<< "${SERVER_IP_LIST//,/ }"
SERVER_NUM=${#X[@]}
ip_list="[$(printf '"%q",' "${X[@]}")"
ip_list="${ip_list%,}]"	
if ! [[ $SERVER_NUM -eq 1 || $SERVER_NUM -eq 3 || $SERVER_NUM -eq 5 || $SERVER_NUM -eq 7 ]]; then
    error "es server数量不满足要求, 建议生产环境使用3,5,7奇数台es"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装
if ! rpm -q elasticsearch &>/dev/null; then
    log "yum install elasticsearch-${ES_VERSION}"
    unset JAVA_HOME
    yum -q -y install elasticsearch-"${ES_VERSION}" || error "elsticsearch7 安装失败"
    if ! rpm -q elasticsearch-"${ES_VERSION}" &>/dev/null;then
        error "elasticsearch7 安装失败"
    fi
fi

# 创建目录
log "创建$DATA_DIR/ $LOG_DIR/目录"
install -o "elasticsearch" -g "elasticsearch" -d "$DATA_DIR/" "$LOG_DIR/"


# 修改内核参数
if [[ -d /etc/sysctl.d/ ]]; then
    if ! grep -q vm.max_map_count /etc/sysctl.d/elasticsearch.conf 2>/dev/null; then
        echo "vm.max_map_count=512000" >> /etc/sysctl.d/elasticsearch.conf
    fi
else
    if ! grep -q vm.max_map_count /etc/sysctl.conf 2>/dev/null; then
        echo "vm.max_map_count=512000" >> /etc/sysctl.conf
    fi
fi
sysctl -p >/dev/null

# 修改elasticsearch的max open files
if [[ -d /etc/security/limits.d/ ]]; then
    if ! grep -q elasticsearch /etc/security/limits.d/elasticsearch.conf 2>/dev/null; then
        echo 'elasticsearch soft nofile 204800' >> /etc/security/limits.d/elasticsearch.conf
        echo 'elasticsearch hard nofile 204800' >> /etc/security/limits.d/elasticsearch.conf
    fi
else
    if ! grep -q elasticsearch /etc/security/limits.conf 2>/dev/null; then
        echo 'elasticsearch soft nofile 204800' >> /etc/security/limits.conf
        echo 'elasticsearch hard nofile 204800' >> /etc/security/limits.conf
    fi
fi

# 生成es的node-id
myid=
for ((i=0; i<SERVER_NUM; i++)); do
    if [[ $BIND_ADDR = "${X[$i]}" ]]; then
        myid="$i"
    fi
done
if [[ -z "$myid" ]]; then
    error "bind ip(-b) is not include in ip list(-j), can't auto-generate myid"
fi

# 判断是否安装集群模式es

CONF_NAME=elasticsearch.yml
JVM_MEM=$(awk '/MemAvailable/{print int($2/1024/1024/2)}' /proc/meminfo)
if [[ $SERVER_NUM -eq 1 ]];then
    log "部署单节点集群ES"
    # 生成 es 配置文件
    log "生成 /etc/elasticsearch/$CONF_NAME 配置文件"
    cat > "/etc/elasticsearch/${CONF_NAME}" <<EOF 
cluster.name: bkee-es
node.master: true
node.data: true
node.name: elasticsearch-$myid
node.attr.tag: cold
path.data: $DATA_DIR/
path.logs: $LOG_DIR/
bootstrap.memory_lock: false
bootstrap.system_call_filter: false
network.host: $BIND_ADDR
http.port: $ES_REST_PORT
transport.tcp.port: $ES_TRANSPORT_PORT
discovery.zen.ping.unicast.hosts: ${ip_list}
discovery.zen.minimum_master_nodes: 1

thread_pool.search.queue_size: 1000
thread_pool.write.queue_size: 1000

cluster.routing.allocation.same_shard.host: true
cluster.initial_master_nodes: $ip_list
cluster.max_shards_per_node: 10000

EOF
    log "修改jvm最大内存堆大小为物理内存的一半"
    if [[ ${JVM_MEM} -eq 0 ]] ;then
        sed -i "s/-Xmx1g/-Xmx256m/g" /etc/elasticsearch/jvm.options
        sed -i "s/-Xms1g/-Xms256m/g" /etc/elasticsearch/jvm.options
    else
        sed -i "s/-Xmx1g/-Xmx${JVM_MEM}g/g" /etc/elasticsearch/jvm.options
        sed -i "s/-Xms1g/-Xms${JVM_MEM}g/g" /etc/elasticsearch/jvm.options
    fi
else
    log "部署${SERVER_NUM}节点集群ES"
    # 生成 es 配置文件
    log "生成 /etc/elasticsearch/$CONF_NAME 配置文件"
    cat > "/etc/elasticsearch/${CONF_NAME}" <<EOF 
cluster.name: bkee-es
node.master: true
node.data: true
node.name: elasticsearch-$myid
node.attr.tag: cold
path.data: $DATA_DIR/
path.logs: $LOG_DIR/
bootstrap.memory_lock: false
bootstrap.system_call_filter: false
network.host: $BIND_ADDR
http.port: $ES_REST_PORT
transport.tcp.port: $ES_TRANSPORT_PORT
discovery.zen.ping.unicast.hosts: ${ip_list}
discovery.zen.minimum_master_nodes: 2

thread_pool.search.queue_size: 1000
thread_pool.write.queue_size: 1000

cluster.routing.allocation.same_shard.host: true
cluster.initial_master_nodes: $ip_list
cluster.max_shards_per_node: 10000
EOF
    log "修改jvm最大内存堆大小为物理内存的一半"
    sed -i "s/-Xmx1g/-Xmx${JVM_MEM}g/g" /etc/elasticsearch/jvm.options
    sed -i "s/-Xms1g/-Xms${JVM_MEM}g/g" /etc/elasticsearch/jvm.options
fi

# 启动es
log "启动elasticsearch"
systemctl start elasticsearch.service

log "检查elasticsearch 状态"
if ! systemctl status "elasticsearch"; then
    log "请检查启动日志，使用命令：journalctl -u elasticsearch 查看失败原因"
    log "手动修复后，使用命令：systemctl start elasticsearch 启动并确认是否启动成功"
    log "启动成功后，使用命令：systemctl enable elasticsearch 设置开机启动"
    exit 100
else
    log "设置Es实例 elasticsearch 开机启动"
    systemctl enable "elasticsearch"
fi
