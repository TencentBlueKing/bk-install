#!/usr/bin/env bash
# 用途：在已经运行的单实例的mongodb上，配置带key验证的replicaset集群
# 参考文档：
#       1. https://docs.mongodb.com/manual/tutorial/deploy-replica-set/
#       2. https://docs.mongodb.com/manual/tutorial/deploy-replica-set-with-keyfile-access-control/#deploy-repl-set-with-auth

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
CLUSTER_IP_LIST=
CLIENT_PORT=27017
ENCRYPT_KEY=
KEY_PATH=/etc/mongod.key
ACTION=
MONGODB_USER=${MONGODB_USER:-""}
MONGODB_PASSWORD=${MONGODB_PASSWORD:-""}
REPLICA_SET_NAME=rs0

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -a, --action          [必填] "动作：[ config | init ] config的动作需要在多台mongodb实例上。init的动作只在任选一台上操作。 ]
            [ -e, --encrypt-key     [必填] "动作为 config 时，指定内部集群认证的key，长度为6~1024的base64字符集的字符串" ]
            [ -k, --keyfile         [选填] "动作为 config 时，存放encrypt key的路径,默认为 /etc/mongod.key "]
            [ -j, --join            [必填] "动作为 init 时，集群的ip列表逗号分隔，奇数（3，5，7）个" ]
            [ -u, --username        [选填] "动作为 init 时，配置mongodb集群的超级管理员用户名。]
            [ -p, --password        [选填] "动作为 init 时，配置mongodb集群的超级管理员密码。]
            [ -P, --port            [选填] "动作为 init 时，配置mongodb的监听端口，默认为27017。]
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

fail () {
    echo "$@" 1>&2
    exit 1
}

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

version () {
    echo "$PROGRAM version $VERSION"
}

get_self_ip () {
    local dst=$1
    ip route get "$dst" | awk '{print $NF ; exit }'
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -a | --action)
            shift
            ACTION=$1
            ;;
        -k | --keyfile )
            shift
            KEY_PATH=$1
            ;;
        -j | --join-ip )
            shift
            CLUSTER_IP_LIST=$1
            ;;
        -e | --encrypt-key )
            shift
            ENCRYPT_KEY=$1
            ;;
        -u | --username)
            shift
            MONGODB_USER=$1
            ;;
        -p | --password)
            shift
            MONGODB_PASSWORD=$1
            ;;
        -P | --port)
            shift
            CLIENT_PORT=$1
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

# 参数合法性有效性校验
case $ACTION in 
    init )
        if [[ -z "$CLUSTER_IP_LIST" ]]; then
            warning "必须指定(-j --join-ip) 组成集群的ip列表"
        fi
        if [[ -z $MONGODB_USER || -z $MONGODB_PASSWORD ]]; then
            warning "当action为init时，必须指定用户名和密码"
        fi
        ;;
    config )
        if [[ -z "$ENCRYPT_KEY" ]]; then
            warning "必须指定(-e keystring) 随机字符串"
        fi
        ;;
    *)
        warning "-a(--action)必须为init或者config"
        ;;
esac

if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 开始配置
if [[ $ACTION = "config" ]]; then
    # generate key file
    log "生成 $KEY_PATH 并设置权限为400"
    echo -n "$ENCRYPT_KEY" > "$KEY_PATH"
    chown mongod.mongod "$KEY_PATH"
    chmod 400 /etc/mongod.key

    log "修改/etc/mongod.conf，增加replica和keyfiles设定"
    sed -i '/^replication:/,/^$/d' /etc/mongod.conf
    cat <<EOF >> /etc/mongod.conf
replication:
  replSetName: $REPLICA_SET_NAME
security:
  keyFile: $KEY_PATH
EOF

    log "重启mongod 服务"
    systemctl restart mongod
else
    read -r -a X <<< "${CLUSTER_IP_LIST//,/ }"
    lan_ip=$(get_self_ip "${X[@]}")
    members=$(
        {
            for ((i=0; i<${#X[@]}; i++)); do
                if [[ "$lan_ip" = "${X[$i]}" ]]; then
                    echo -n "{_id: $i, priority: 2, host: \"${X[$i]}:$CLIENT_PORT\"},"
                else
                    echo -n "{_id: $i, host: \"${X[$i]}:$CLIENT_PORT\"},"
                fi
            done
        }
    )
    members=${members%?}	#remove last characters

    # init replica set config
    log "start rs.initiate() for mongodb cluster"
    mongo --port "$CLIENT_PORT" --eval "db.disableFreeMonitoring();"    # 取消4.2.2版本的监控信息声明
    mongo --port "$CLIENT_PORT" --eval "rs.initiate( { _id : \"$REPLICA_SET_NAME\", members: [ $members ] })"
    log "waiting for rs.initiate to complete(timeout=20s)"
    mongo --port "$CLIENT_PORT" <<END
var timeout = 10
while(!db.isMaster().ismaster) {
        if ( timeout <= 0 ) { 
                break
        } else {
                sleep(2000)
                --timeout
        }
} 
if ( timeout <= 0 ) {
        print("RS setup timeout")
} else {
        print("RS setup done")
}
END

    log "get rs status"
    mongo --port "$CLIENT_PORT" --eval "rs.status()"

    log "add mongodb admin account. after that localhost interface also need auth"
    mongo --port "$CLIENT_PORT" <<END || fail "创建mongodb管理员失败"
admin = db.getSiblingDB("admin")
admin.createUser(
{
  user: "$MONGODB_USER",
  pwd: "$MONGODB_PASSWORD",
  roles: [
	{ role: "userAdminAnyDatabase", db: "admin" },
        { role : "clusterAdmin",  db : "admin" },
        { role : "root",  db : "admin" },
]})
END
fi