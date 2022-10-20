#!/usr/bin/env bash
# 安装，配置 mongodb cluster，2.x版本
# 参考文档： 
#           1. https://docs.mongodb.com/manual/tutorial/install-mongodb-on-red-hat/
#           2. https://docs.mongodb.com/manual/tutorial/deploy-replica-set/

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
MONGODB_VERSION="2.4.10"
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
src_dir='/data/src'
mongo_tar="mongodb-linux-x86_64-${MONGODB_VERSION}.tgz"
mongo_dir="mongodb-linux-x86_64-${MONGODB_VERSION}"
cd ${src_dir} || error "cd ${src_dir} fail"
tar xf ${src_dir}/${mongo_tar} || error "unzip mongodb install package fail"
cp -a ${mongo_dir}/bin/* /usr/bin/ || error "copy bin files fail"

# 配置文件生成
log "生成配置文件/etc/mongod.conf"
mongo_conf_file='/etc/mongod.conf'
PID_PATH='/var/run/mongodb'
cat >${mongo_conf_file} <<EOF
logpath=${LOG_DIR}/mongod.log    
logappend=true    
fork=true    
dbpath=${DATA_DIR}   
journal=true    
directoryperdb=true    
auth=false
bind_ip=${BIND_ADDR}
port=${CLIENT_PORT}
pidfilepath=${PID_PATH}/mongod.pid
master=true
EOF

# 判断并创建目录
if ! [[ -d $DATA_DIR ]]; then
    mkdir -p "$DATA_DIR"
fi
if ! [[ -d $LOG_DIR ]]; then
    mkdir -p "$LOG_DIR"
fi
if [[ ! -d ${PID_PATH} ]];then
    mkdir -p ${PID_PATH}
fi


# 生成systemd配置文件
log "生成systemd配置文件"
mongo_systemd_conf='/usr/lib/systemd/system/mongod.service'
cat > ${mongo_systemd_conf} <<EOF
[Unit]  
Description=mongodb   
After=network.target remote-fs.target nss-lookup.target  
  
[Service]  
Type=forking  
ExecStart=/usr/bin/mongod --config ${mongo_conf_file} 
ExecReload=/bin/kill -s HUP $MAINPID  
ExecStop=/usr/bin/mongod --shutdown --config ${mongo_conf_file}
PrivateTmp=true  
    
[Install]  
WantedBy=multi-user.target
EOF

log "启动mongod，并设置开机启动mongod"
systemctl daemon-reload
systemctl enable mongod
systemctl start mongod
systemctl status mongod
