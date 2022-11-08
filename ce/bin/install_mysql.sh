#!/usr/bin/env bash
# 用途：安装多实例的MySQL 5.7，使用systemd托管
# 参考文档：- https://dev.mysql.com/doc/refman/5.7/en/using-systemd.html#systemd-multiple-mysql-instances
#          - https://dev.mysql.com/doc/mysql-secure-deployment-guide/5.7/en/

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
MYSQL_VERSION="5.7.29"
BIND_ADDR="127.0.0.1"
PORT=3306
DATA_DIR="/var/lib/mysql"
LOG_DIR="/var/log/mysql"
IS_INIT=0
NAME="mysql"
PASSWORD=
PREFIX=/usr/local

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -n, --name        [必填] "部署的mysql实例名称" ]
            [ -P, --port        [必填] "部署的mysql端口号" ]
            [ -p, --password    [必填] "部署的mysql密码" ]
            [ -d, --data-dir    [必填] "部署的mysql实例的数据目录前缀" ]
            [ -l, --log-dir     [必填] "部署的mysql实例的日志目录前缀" ]
            [ -b, --bind        [可选] "监听的网卡地址,默认为127.0.0.1" ]
            [ -i, --init        [可选] "初次部署时，需要加上" ]

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
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -n | --name )
            shift
            NAME=$1
            ;;
        -P | --port)
            shift
            PORT=$1
            ;;
        -p | --password )
            shift
            PASSWORD=$1
            ;;
        -i | --init)
            IS_INIT=1
            ;;
        -d | --data-dir)
            shift
            DATA_DIR="$1"
            ;;
        -l | --log-dir)
            shift
            LOG_DIR="$1"
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

# 检查bind addr
if ! [[ $BIND_ADDR =~  ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    warning "$BIND_ADDR is not a valid bind-address option"
fi
# 监听端口检查
if lsof -i:$PORT -sTCP:LISTEN 1>/dev/null 2>&1;then
    log "$PORT already listen" && exit 0
fi
# 参数合法性有效性校验，这些可以使用通用函数校验。
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi


# 安装依赖
if ! rpm -ql mysql-community-server-${MYSQL_VERSION} &>/dev/null; then
    log "installing mysql-community-server-${MYSQL_VERSION}"
    yum -q -y install mysql-community-server-${MYSQL_VERSION} || error "安装mysql server失败"
fi

install -o mysql -g mysql -d "${LOG_DIR}"
# 多实例分开datadir
install -o mysql -g mysql -d "${DATA_DIR}"/"${NAME}"/{tmp,binlog,relaylog,data}
install -o mysql -g mysql -d /etc/mysql

# 生成server的my.cnf
cat > /etc/mysql/"${NAME}.my.cnf" <<EOF
[mysqld]
character-set-server=utf8
datadir=${DATA_DIR}/${NAME}/data
tmpdir=${DATA_DIR}/${NAME}/tmp
socket=/var/run/mysql/${NAME}.mysql.socket
bind-address=$BIND_ADDR
port=$PORT
user=mysql
slow_query_log=1
slow_query_log_file=${LOG_DIR}/${NAME}.slow-query.log
log-error=${LOG_DIR}/${NAME}.mysqld.log
lc_messages_dir = /usr/share/mysql

max_connections=3000
sql_mode=''

# innodb
default-storage-engine=innodb
innodb_data_file_path=ibdata1:1G:autoextend
innodb_file_format=Barracuda
innodb_file_per_table=1
innodb_flush_log_at_trx_commit=0
innodb_lock_wait_timeout=50
innodb_log_buffer_size=32M
innodb_log_file_size=256M
innodb_log_files_in_group=4
innodb_strict_mode=off
innodb_thread_concurrency=16
interactive_timeout=10800
key_buffer_size=64M
log_bin=${DATA_DIR}/${NAME}/binlog/binlog.bin
log_bin_trust_function_creators=1
log_error_verbosity=1
log_slave_updates=1
log_slow_admin_statements=ON
log_timestamps=SYSTEM
long_query_time=1
max_allowed_packet=256M
max_binlog_size=256M
max_connect_errors=99999999
myisam_sort_buffer_size=64M
net_read_timeout=999
net_write_timeout=999
performance_schema=OFF
query_cache_size=0
query_cache_type=1
read_buffer_size=2M
relay_log_recovery=1
relay-log=${DATA_DIR}/${NAME}/relaylog/relay-log.bin
replicate-wild-ignore-table=mysql.%
secure_file_priv=
show_compatibility_56=on
skip-external-locking
skip-name-resolve
skip-symbolic-links
slave_compressed_protocol=1
slave_exec_mode=idempotent
slave_parallel_workers=0
sort_buffer_size=2M
stored_program_cache=1024
sync_binlog=0
table_open_cache=2000
thread_cache_size=8
wait_timeout=10800

server-id=1
EOF

# 生成client的conf
cat > /etc/mysql/"${NAME}.client.conf" <<EOF
[client]
default-character-set=utf8
port=${PORT}
socket=/var/run/mysql/${NAME}.mysql.socket
EOF

# 生成mysql@.service, 和mysql.target
echo '[Unit]' > /etc/systemd/system/mysql.target
echo 'Description=mysql target allowing to start/stop all mysql@.service instances at once' >> /etc/systemd/system/mysql.target
cat > /etc/systemd/system/mysql@.service <<EOF
[Unit]
Description=MySQL Server
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target
PartOf=mysql.target

[Install]
WantedBy=multi-user.target

[Service]
User=mysql
Group=mysql
Type=forking
RuntimeDirectory=mysql
RuntimeDirectoryMode=755
PIDFile=/var/run/mysql/%i.mysqld.pid
# Disable service start and stop timeout logic of systemd for mysqld service.
TimeoutSec=0

# Start main service
ExecStart=/sbin/mysqld --defaults-file=/etc/mysql/%i.my.cnf \
        --daemonize --pid-file=/var/run/mysql/%i.mysqld.pid $MYSQLD_OPTS 

# Use this to switch malloc implementation
EnvironmentFile=-/etc/sysconfig/%i.mysql

LimitNOFILE=10000
Restart=on-failure
RestartPreventExitStatus=1
PrivateTmp=false
EOF

# 初次安装需要初始化数据库, 并获取临时root密码
LOG_ERROR_FILE="${LOG_DIR}/${NAME}.mysqld.log"
TMP_ROOT_PASSWORD=
if [[ $IS_INIT -eq 1 ]]; then
    if ! /sbin/mysqld --defaults-file=/etc/mysql/"${NAME}.my.cnf" --initialize; then
        error "初始化mysql@${NAME}失败，请参考日志 $LOG_ERROR_FILE 确认报错信息。"
    else
        TMP_ROOT_PASSWORD=$(awk '/A temporary password is generated/ { print $NF }' "$LOG_ERROR_FILE" | tail -1)
    fi
fi

# 加载配置，启动mysqld实例
if systemd-analyze verify "/etc/systemd/system/mysql@${NAME}.service"; then
    log "重新加载systemd"
    systemctl daemon-reload
    log "启动MySQL实例 mysql@${NAME}"
    systemctl start "mysql@${NAME}.service"
    log "检查mysql@${NAME} 状态"
    if ! systemctl status "mysql@${NAME}.service"; then 
        log "请检查启动日志，使用命令：journalctl -u mysql@${NAME} 查看失败原因"
        log "手动修复后，使用命令：systemctl start mysql@${NAME} 启动并确认是否启动成功"
        log "启动成功后，使用命令：systemctl enable mysql@${NAME} 设置开机启动"
        exit 100
    else
        log "设置Mysql实例 mysql@${NAME} 开机启动"
        systemctl enable mysql@"${NAME}"
    fi

    # 设置 mysql root随机密码为用户指定的密码
    if [[ -n "$PASSWORD" && $IS_INIT -eq 1 ]]; then
        if MYSQL_PWD="$TMP_ROOT_PASSWORD" /usr/bin/mysql --defaults-file="/etc/mysql/${NAME}.client.conf" \
            -uroot --connect-expired-password \
            -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$PASSWORD')"; then
            log "设置mysql的root@localhost密码为: ${PASSWORD:0:${#PASSWORD}-4}****"
        fi
    fi
else
    error "systemd服务定义文件(/etc/systemd/system/mysql@.service)有误"
fi

# 去掉mysqld.service的开机启动，否则会造成重启机器后，3306端口被mysqld占用的问题
if systemctl is-enabled mysqld.service &>/dev/null; then
    systemctl disable mysqld.service &>/dev/null
fi