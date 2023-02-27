#!/usr/bin/env bash
# 安装，配置 mongodb cluster 
# 参考文档： 
#           1. https://docs.mongodb.com/manual/tutorial/install-mongodb-on-red-hat/
#           2. https://docs.mongodb.com/manual/tutorial/deploy-replica-set/

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
MONGODB_VERSION="4.2.3"
BIND_ADDR="127.0.0.1"
CLIENT_PORT=27017
DATA_DIR="/var/lib/mongodb"
LOG_DIR="/var/log/mongodb"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -p, --port            [选填] "部署的mongodb listen port, 默认27017" ]
            [ -b, --bind            [选填] "mongodb的监听地址默认为127.0.0.1" ]
            [ -d, --data-dir        [选填] "mongodb的数据目录，默认为/var/lib/mongodb" ]
            [ -l, --log-dir         [选填] "mongodb的日志目录，默认为/var/log/mongodb" ]
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
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -p | --port )
            shift
            CLIENT_PORT=$1
            ;;
        -d | --data-dir )
            shift
            DATA_DIR=$1
            ;;
        -l | --log-dir )
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

if ! [[ "$BIND_ADDR" =~ ^[0-9] ]]; then
    warning "$BIND_ADDR is not a valid address"
fi

# 参数合法性有效性校验
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 安装 mongodb
if ! rpm -ql mongodb-org-"$MONGODB_VERSION" &>/dev/null; then
    yum install -y mongodb-org-"$MONGODB_VERSION" mongodb-org-server-"$MONGODB_VERSION" \
        mongodb-org-shell-"$MONGODB_VERSION" mongodb-org-mongos-"$MONGODB_VERSION" \
        mongodb-org-tools-"$MONGODB_VERSION" || error "安装mongodb-$MONGODB_VERSION 失败"
fi

# 判断并创建目录
if ! [[ -d $DATA_DIR ]]; then
    mkdir -p "$DATA_DIR"
fi
if ! [[ -d $LOG_DIR ]]; then
    mkdir -p "$LOG_DIR"
fi
chown mongod.mongod "$DATA_DIR" "$LOG_DIR"

# 修改mongodb配置
log "修改mongodb主配置文件 /etc/mongod.conf"

# 如果监听ip不是localhost才需要修改配置
if ! [[ $BIND_ADDR = "127.0.0.1" || $BIND_ADDR = "localhost" ]]; then
    sed -i "/bindIp/s/127.0.0.1/127.0.0.1, $BIND_ADDR/" /etc/mongod.conf
fi

log "限制mongodb的wiredTiger内存 /etc/mongod.conf"
sed -i "s/#\? *engine: *wiredTiger.*/    engine: wiredTiger\n      wiredTiger:\n        engineConfig:\n          cacheSizeGB: 4/" "/etc/mongod.conf"

# Check if the configuration file was modified
if ! grep -q "cacheSizeGB: 4" "/etc/mongod.conf"; then
    echo "WiredTiger cache size has been set to 4."
else
    echo "WiredTiger cache size is already set to 4."
fi

# 增加logrotate参数为reopen
sed -i '/logRotate/d' /etc/mongod.conf 
sed -i '/logAppend/a\  logRotate: reopen' /etc/mongod.conf

sed -i "/  dbPath/s,/var/lib/mongo,$DATA_DIR," /etc/mongod.conf
sed -i "/  path:/s,/var/log/mongodb,$LOG_DIR," /etc/mongod.conf
sed -i "/  port:/s,27017,$CLIENT_PORT," /etc/mongod.conf
# 如果单机混搭多实例mongodb时，建议配置下面选项
# sed -i -e '/wiredTiger:/ s/^#//' -e '/wiredTiger:/a\    engineConfig:\n      cacheSizeGB: 1' /etc/mongod.conf

# 配置系统的logrotate
cat <<EOF > /etc/logrotate.d/mongodb
$LOG_DIR/*.log {
    daily
    rotate 14
    size 100M
    compress
    dateext
    missingok
    notifempty
    sharedscripts
    postrotate
        /bin/kill -SIGUSR1 \`cat /var/run/mongodb/mongod.pid 2> /dev/null\` 2> /dev/null || true
    endscript
}
EOF

log "启动mongod，并设置开机启动mongod"
systemctl enable --now mongod
systemctl status mongod