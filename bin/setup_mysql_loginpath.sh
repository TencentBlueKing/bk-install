#!/usr/bin/env bash

set -euo pipefail

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局参数
PORT=3306
PASSWORD=
HOST=
USERNAME=
LOGIN_PATH=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]

            [ -n, --name/--login-path   [必填] "配置的loginpath名字，传递给mysql_config_editor的--login-path=" ]
            [ -h, --host/--socket       [必填] "连接的主机/socket路径" ]
            [ -P, --port                [选填] "连接的主机的端口，默认为3306" ]
            [ -u, --user                [必填] "连接的用户名" ]
            [ -p, --password            [必填] "连接的密码" ]

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
        -u | --user )
            shift
            USERNAME=$1
            ;;
        -p | --password )
            shift
            PASSWORD=$1
            ;;
        -n | --login-path | --name )
            shift
            LOGIN_PATH=$1
            ;;
        -h | --host | --socket )
            shift
            HOST=$1
            ;;
        -P | --port )
            shift
            PORT=$1
            ;;
        --help | '-?' )
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

if [[ -z "$LOGIN_PATH" || -z "$USERNAME" || -z "$PASSWORD" || -z "$HOST" ]]; then
    usage_and_exit 1
fi

if [[ -S $HOST ]]; then
    # is a socket dest
    expect -c "
    spawn mysql_config_editor set --skip-warn --login-path=$LOGIN_PATH --socket=$HOST --user=$USERNAME --password
    expect -nocase \"Enter password:\" {send \"$PASSWORD\r\"; interact}
    "
else
    # else is a host
    expect -c "
    spawn mysql_config_editor set --skip-warn --login-path=$LOGIN_PATH --host=$HOST --user=$USERNAME --port=$PORT --password
    expect -nocase \"Enter password:\" {send \"$PASSWORD\r\"; interact}
    "
fi