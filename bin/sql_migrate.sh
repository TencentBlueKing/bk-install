#!/usr/bin/env bash
# sql_migrate: load sql into MYSQL on a defined file pattern, and record
# SQL Filename Example:
#        0001_<module>_<timestamp1>_mysql.sql
#        0002_<module>_<timestamp2>_mysql.sql
# when load sql successfull record the filename & md5sum into ~/.migrate/
# and chattr +i to prevent from deletion by accident.
# Usage: sql_migrate.sh --login-path <dest> <path_sql_files>

set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# where to store migrate record
MIGRATE_DIR=$HOME/.migrate

# which mysql instance should sql apply to
MYSQL_LOGIN_PATH=

# SQL files path array
SQL=()

usage () {
    cat <<EOF
用法: 
    $PROGRAM --login-path <name> sql1 sql2 sql3 ...
            [ -h --help -?  查看帮助 ]
            [ -n, --login-path  [必填] "导入的mysql实例名称" ]
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

tag_file () {
    local dir=$1
    local file=$2
    local filename=${file##*/}
    [[ -d "$dir" ]] || mkdir -p $dir
    md5sum "$file" | cut -d' ' -f1 > "$dir/$filename" && \
    chattr +i "$dir/$filename"
    return $?
}

# parse command line args
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        --login-path | -n )
            shift
            MYSQL_LOGIN_PATH=$1
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
            SQL+=("$1")
            ;;
    esac
    shift 
done 

# check mysql binary
if ! command -v mysql &>/dev/null; then
    warning "mysql command is not exists."
fi
# check login-path is reachable 
if ! mysql --login-path="$MYSQL_LOGIN_PATH" -e 'show processlist' >/dev/null; then
    warning "mysql --login-path=$MYSQL_LOGIN_PATH is not valid"
fi
# check SQL file exists
for f in "${SQL[@]}"; do
    [[ -r $f ]] || warning "$f is not readable."
done
# check errcode
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

[[ -d $MIGRATE_DIR ]] || mkdir -p "$MIGRATE_DIR"

for sql in "${SQL[@]}"; do
    sql_name=${sql##*/}
    if [[ -f $MIGRATE_DIR/${sql_name} ]]; then
        log "$sql already import, skip."
    else
        if mysql --login-path="$MYSQL_LOGIN_PATH" < "$sql"; then
            echo "$sql import done."
            tag_file "$MIGRATE_DIR" "$sql"
        else
            echo "$sql import err, Abort."
            exit 1
        fi
    fi
done