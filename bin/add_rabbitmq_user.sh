#!/usr/bin/env bash
# 用途：用来封装rabbitmq管理的脚本

set -euo pipefail

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局变量
MQ_USER=
MQ_PASSWORD=
MQ_VHOST=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -u, --user            [必选] "添加的账号名" ]
            [ -p, --password        [必选] "添加的账号名对应的密码" ]
            [ -h, --vhost           [可选] "添加的账号关联的vhost，默认和账号一致" ]
            [ -v, --version         [可选] 查看脚本版本号 ]
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
# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -u | --user )
            shift
            MQ_USER=$1
            ;;
        -p | --password )
            shift
            MQ_PASSWORD=$1
            ;;
        -h | --vhost)
            shift
            MQ_VHOST=$1
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

# check parameters
if ! command -v rabbitmqctl &>/dev/null; then
    fail "there is no rabbitmqctl on this host. please run script on rabbitmq host"
fi
if [[ -z "$MQ_USER" || -z "$MQ_PASSWORD" ]]; then
    warning "-u , -p must not be empty"
fi
if [[ -z "$MQ_VHOST" ]]; then
    MQ_VHOST=$MQ_USER
fi

 
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

if rabbitmqctl list_users | grep -w "$MQ_USER"; then
    echo "$MQ_USER already exists"
else
    rabbitmqctl add_user "$MQ_USER" "$MQ_PASSWORD" \
        || fail "add rabbitmq user for $MQ_USER failed."

    rabbitmqctl set_user_tags "$MQ_USER" management \
    || fail "set tags for $MQ_USER failed." 
fi

# add user and vhost and permissions


rabbitmqctl add_vhost "$MQ_VHOST" \
    || fail "add vhost for $MQ_USER failed."

rabbitmqctl set_permissions -p "$MQ_VHOST" "$MQ_USER" ".*" ".*" ".*" \
    || fail "set permissions for $MQ_USER failed."

rabbitmqctl set_policy ha-all '^' '{"ha-mode": "all","ha-sync-mode":"automatic"}' -p "$MQ_VHOST" \
    || fail "set ha policy for $MQ_VHOST failed."