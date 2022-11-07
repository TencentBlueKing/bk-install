#!/usr/bin/env bash
# 封装zookeepercli命令行，读取蓝鲸的配置后，拼接链接串然后执行命令
# zookeepercli是golang编写的开源工具，见：https://github.com/outbrain/zookeepercli

# 安全模式
set -euo pipefail 

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/bin
export PATH

PROGRAM=$(basename "$0")
EXITCODE=0

CONFIG=/data/bkee/etc/gse/data.conf
COMMAND=
MODULE=gse
AUTH=false

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -f, --config      [可选] "读取的gse的配置路径，默认为/data/bkee/etc/gse/data.conf" ]
            [ -c, --command     [必选] "运行的zk命令" ]
            [ -m, --module      [可选] "取值为：gse或cmdb，默认是gse" ]
            [ -a, --auth        [可选] "是否带认证串执行" ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -f | --config )
            shift
            CONFIG="$1"
            ;;
        -c | --command )
            shift
            COMMAND="$@"
            ;;
        -m | --module )
            shift
            MODULE="$1"
            ;;
        -a | --auth )
            AUTH=true
            ;;
    esac
    shift $(( $# == 0 ? 0 : 1 ))
done

if ! [[ -f "$CONFIG" ]]; then
    warning "$CONFIG doesn't exists."
fi

case $MODULE in 
    gse) 
        if ! grep -q '{' $CONFIG; then
            warning "$CONFIG is not json format,not a valid gse config."
        fi
        ;;
    cmdb)
        if ! grep -q registerServer -q $CONFIG; then
            warning "$CONFIG is not a valid cmdb migration.conf"
        fi
        ;;
    *)
        warning "$MODULE must be gse or cmdb"
        ;;
esac

if [[ -z "$COMMAND" ]]; then
    warning "COMMAND is empty"
fi

if ! hash "zookeepercli" 2>/dev/null; then
    warning "no zookeepercli command found in PATH. please install it."
fi

if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

if [[ $MODULE = gse ]]; then
    ZK_CONN_STR=$(awk '/^[[:blank:]]*"zkhost":/ { split($0,a, /"/); print a[4] }' < "$CONFIG")
    ZK_AUTH_STR=$(awk '/^[[:blank:]]*"zkauth":/ { split($0,a, /"/); print a[4] }' < "$CONFIG")
    ZK_AUTH_USR=${ZK_AUTH_STR%:*}
    ZK_AUTH_PWD=${ZK_AUTH_STR#*:}
elif [[ $MODULE = cmdb ]]; then
    # cmdb auth_str hardcode https://github.com/Tencent/bk-cmdb/blob/e1351efcb898b43a6700d067a71386379b761e2f/src/common/zkclient/zkclient.go#L33
    ZK_CONN_STR=$(awk '/^registerServer:/ {getline; print $NF; exit 0}' "$CONFIG")
    ZK_AUTH_USR=cc
    ZK_AUTH_PWD='3.0#bkcc'
else
    usage_and_exit "$EXITCODE"
fi

if [[ "$AUTH" = true ]]; then
    zookeepercli -auth_usr "$ZK_AUTH_USR" -auth_pwd "$ZK_AUTH_PWD" -servers "$ZK_CONN_STR" -c $COMMAND
else
    zookeepercli -servers "$ZK_CONN_STR" -c $COMMAND
fi
