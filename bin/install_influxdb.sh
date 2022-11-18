#!/usr/bin/env bash
# install_influxdb.sh ：安装，配置influxdb
# 参考文档：
#   1. https://docs.influxdata.com/influxdb/v1.7/introduction/installation/
#   2. https://docs.influxdata.com/influxdb/v1.7/administration/authentication_and_authorization/

set -euo pipefail

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
PREFIX=/data/bkee
INFLUXDB_VERSION=1.7.10
DATA_DIR=/var/lib/influxdb
LOG_DIR=/var/log/influxdb
WAL_DIR=/var/lib/influxdb/wal
BIND_ADDR=127.0.0.1
INFLUXDB_PORT=8086
INFLUXDB_USERNAME=admin
INFLUXDB_PASSWORD=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -b, --bind        [可选] "influxdb监听的ip地址，默认为$BIND_ADDR" ]
            [ -P, --port        [可选] "influxdb监听的端口，默认为$INFLUXDB_PORT" ]
            [ -u, --user        [可选] "influxdb的admin用户，默认为admin" ]
            [ -p, --password    [可选] "influxdb的admin用户密码" ]
            [ -d, --data-dir    [可选] "指定influxdb的数据存放的目录" ]
            [ -w, --wal-dir     [可选] "指定influxdb的wal-dir存放目录" ]
            [ -l, --log-dir     [可选] "指定influxdb的log-dir存放目录" ]
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

check_port_alive () {
    local port=$1

    lsof -i:$port -sTCP:LISTEN 1>/dev/null 2>&1

    return $?
}
wait_port_alive () {
    local port=$1
    local timeout=${2:-10}

    for i in $(seq $timeout); do
        check_port_alive $port && return 0
        sleep 1
    done
    return 1
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -d | --data-dir )
            shift
            DATA_DIR=$1
            ;;
        -w | --wal-dir )
            shift
            WAl_DIR="$1"
            ;;
        -l | --log-dir )
            shift
            LOG_DIR="$1"
            ;;
        -P | --port )
            shift
            INFLUXDB_PORT=$1
            ;;
        -p | --password )
            shift
            INFLUXDB_PASSWORD=$1
            ;;
        -u | --username )
            shift
            INFLUXDB_USERNAME=$1
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

if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 如果没有单独指定wal_dir
if [[ -z $WAL_DIR ]]; then
    WAL_DIR=${DATA_DIR}/wal
fi

# 安装influxdb 如果未安装过
yum -y install influxdb-${INFLUXDB_VERSION}

# 创建目录
install -d -o influxdb -g influxdb "$DATA_DIR"/{meta,data} "${WAL_DIR}" "${LOG_DIR}"

# 修改默认的 /etc/influxdb/influxdb.conf
if [[ ! -r /etc/influxdb/influxdb.conf.orig ]]; then
    cp -a /etc/influxdb/influxdb.conf{,.orig}
fi
sed -i -f <(cat <<EOF
/reporting-disabled/c reporting-disabled = true
/index-version/ { s/#//; s/inmem/tsi1/; }
/query-timeout/ { s/#//; s/= .*/= "30s"/; }
/\[http\]/,/^###/ { 
    /bind-address/ { s/#//; s/ = .*/ = "$BIND_ADDR:$INFLUXDB_PORT"/} 
    / auth-enabled =/ { s/#//; s/false/true/} 
}
/^\[meta\]/,/^###/s,/var/lib/influxdb/meta,$DATA_DIR/meta,
/^\[data\]/,/^###/ { 
    / wal-dir =/s,/var/lib/influxdb/wal,$WAL_DIR, 
    / dir =/s,/var/lib/influxdb/data,$DATA_DIR/data, 
}
EOF
) /etc/influxdb/influxdb.conf
# 配置rsyslog，重定向influxdb的日志
[ -d /etc/rsyslog.d ] || mkdir -p /etc/rsyslog.d
echo "if \$programname == 'influxd' then ${LOG_DIR}/influxd.log" > /etc/rsyslog.d/influxdb.conf

# check config syntax
if rsyslogd -f /etc/rsyslog.conf -N1 2>/dev/null; then
    systemctl restart rsyslog 
else
    echo "check /etc/rsyslog.d/influxdb.conf syntax failed" >&2
    exit 1
fi

# change logrotate.d
if [[ -f /etc/logrotate.d/influxdb ]]; then
    sed -i "1c ${LOG_DIR}/influxd.log {" /etc/logrotate.d/influxdb 
fi

# 启动influxdb
systemctl enable --now influxdb
systemctl status influxdb

# 检查监控
wait_port_alive  ${INFLUXDB_PORT} 10
http_code=$(curl -s -I -o /dev/null -w "%{http_code}" "$BIND_ADDR:$INFLUXDB_PORT"/ping)
if [[ $http_code -ne 204 ]]; then
    log "influxd($BIND_ADDR:$INFLUXDB_PORT) 启动失败， 请检查journalctl -u influxd日志"
    exit 1
fi

# 创建admin账户，如果指定了密码
if [[ -n "$INFLUXDB_PASSWORD" ]]; then
    if influx -host "$BIND_ADDR" -port "$INFLUXDB_PORT" -execute "CREATE USER $INFLUXDB_USERNAME WITH PASSWORD '$INFLUXDB_PASSWORD' WITH ALL PRIVILEGES"; then
        log "创建influxdb管理员账户成功"
    else
        log "创建influxdb管理员账户失败"
        exit 2
    fi
fi
