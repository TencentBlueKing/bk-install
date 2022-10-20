#!/usr/bin/env bash
# 用途：连上本机的mysql，用root账号给提供的ip授权，登录mysql的信息预设了先使用mysql_config_editor配置好。
# 参考：https://dev.mysql.com/doc/mysql-security-excerpt/5.7/en/password-security-user.html

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
LOGIN_PATH=
MYSQL_USER=
MYSQL_PASSWORD=
HOST_LIST=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -n, --login-path  [必选] 指定mysql链接的mysql实例配置名，具体含义参考mysql_config_editor命令 ]
            [ -u, --user        [必选] 指定授权的用户名 ]
            [ -p, --password    [必选] 指定授权的用户名对应的密码 ]
            [ -H, --host        [必选] 指定授权的主机ip列表，逗号分隔 ]

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
        -n | --login-path )
            shift
            LOGIN_PATH=$1
            ;;
        -u | --user)
            shift
            MYSQL_USER=$1
            ;;
        -p | --password )
            shift
            MYSQL_PASSWORD=$1
            ;;
        -H | --host )
            shift
            HOST_LIST=$1
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
if [[ -z $MYSQL_USER || -z $MYSQL_PASSWORD || -z $LOGIN_PATH || -z $HOST_LIST ]]; then 
    warning "--user, --password, --login-path, --host 都必须指定"
fi
if ! [[ $HOST_LIST =~ ^[0-9.,]+$ ]]; then
    warning "--host 指定的格式不对，逗号分隔的ip列表，无空格字符。"
fi
if ! command -v mysql &>/dev/null; then
    warning "mysql命令不存在,请检查mysql是否安装成功,PATH是否包含正确路径"
fi
if ! command -v mysqladmin &>/dev/null; then
    warning "mysqladmin命令不存在,请检查mysql是否安装成功,PATH是否包含正确路径"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

#先判断login-path是否正确能连上，然后循环遍历HOST_LIST授权。
if mysqladmin --login-path="$LOGIN_PATH" ping >/dev/null ; then
    IFS="," read -r -a hosts <<<"$HOST_LIST"
    for h in "${hosts[@]}"; do
        GRANT_SQL="GRANT ALL ON *.* TO $MYSQL_USER@$h IDENTIFIED BY '$MYSQL_PASSWORD'"
        if ! mysql --login-path="$LOGIN_PATH" -e "$GRANT_SQL"; then
            error "给 $MYSQL_USER@$h 授权失败"
        else
            log "$MYSQL_USER@$h 授权成功"
        fi
    done
else
    error "请检查使用 mysql --login-path=$LOGIN_PATH 是否能免密连上"
fi