#!/usr/bin/env bash
# iam_migrate: 注册每个系统的权限模型配置（json格式）到iam
# json Filename Example:
#        0001_bk_paas_20190619-1632_iam.json
#        0002_bk_paas_20190620-1000_iam.json
#        0001_bk_job_20190620-2040_iam.json
#        0001_bk_cmdb_20190619-1020_iam.json
# when load json successfull record the filename & md5sum into ~/.migrate/
# and chattr +i to prevent from deletion by accident.
# Usage: iam_migrate.sh -t <iam_url> -f <json_file> -a <app_code> -s <app_secret>

set -euo pipefail

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# BKIAM api
BKIAM_URL=http://bkiam.service.consul:5001

APP_CODE=
APP_SECRET=

BKIAM_TOOL="${SELF_DIR}"/bkiam_do_migrate.py

# where to store migrate record
MIGRATE_DIR=$HOME/.migrate
PYTHON_BIN_PATH=/opt/py36/bin/python

# SQL files path array
JSON=()

ENV_FILE=

usage () {
    cat <<EOF
用法: 
    $PROGRAM -t <iam_url> -a <app_code> -s <app_secret> <json_file1> <json_file2> ...
            [ -h --help -?  查看帮助 ]
            [ -t, --iam-url     [可选] "默认为 $BKIAM_URL" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]
            [ -a, --app-code    [必选] "app code" ]
            [ -s, --app-secret  [必选] "app secret" ]
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
        --env-file | -e )
            shift
            ENV_FILE=$1
            ;;
        --iam-url | -t )
            shift
            BKIAM_URL=$1
            ;;
        --app-code | -a )
            shift
            APP_CODE=$1
            ;;
        --app-secret | -s )
            shift
            APP_SECRET=$1
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
            JSON+=("$1")
            ;;
    esac
    shift 
done 

# check empty
if [[ -z $APP_CODE || -z $APP_SECRET ]]; then
    warning "APP_CODE or APP_SECRET is empty"
fi
if ! [[ $(curl -s --connect-timeout 2 $BKIAM_URL/healthz) = "ok" ]]; then
    warning "$BKIAM_URL/healthz return error"
fi
if ! [[ -f $BKIAM_TOOL ]]; then
    warning "there is no $BKIAM_TOOL script."
fi
if ! [[ "$($PYTHON_BIN_PATH --version)" = *3.6* ]]; then
    warning "$PYTHON_BIN_PATH 不存在或者版本不等于3.6.x"
fi
# check json file exists
for f in "${JSON[@]}"; do
    [[ -r $f ]] || warning "$f is not readable."
done
# check errcode
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

[[ -d $MIGRATE_DIR ]] || mkdir -p "$MIGRATE_DIR"

for json in "${JSON[@]}"; do
    json_name=${json##*/}
    if [[ -f $MIGRATE_DIR/${json_name} ]]; then
        log "$json already import, skip."
    else
        if ! grep -Po '__[A-Z][A-Z0-9]+(_[A-Z0-9]+){0,9}__' $json> /dev/null;then
            json=$json
        else
            if  ! [ -z $ENV_FILE ];then
                tmpfile=$(mktemp /tmp/iam_json.XXXXXXXXX)
                "${SELF_DIR}"/render_tpl  -e "$ENV_FILE" -n  "${json}"> "${tmpfile}" && echo "${json} 渲染为 ${tmpfile}"
                if grep -Po '__[A-Z][A-Z0-9]+(_[A-Z0-9]+){0,9}__' "${tmpfile}" > /dev/null;then 
                    error "${json} 渲染失败"
                else
                    if $PYTHON_BIN_PATH "${SELF_DIR}"/bkiam_do_migrate.py -t "$BKIAM_URL" -a "$APP_CODE" -s "$APP_SECRET" -f "$tmpfile"; then
                        echo "$json import done."
                        tag_file "$MIGRATE_DIR" "$json"
                        exit 0
                    else
                        echo "$json import err, Abort."
                        exit 1
                    fi
                fi
            fi
        fi

        if $PYTHON_BIN_PATH "${SELF_DIR}"/bkiam_do_migrate.py -t "$BKIAM_URL" -a "$APP_CODE" -s "$APP_SECRET" -f "$json"; then
            echo "$json import done."
            tag_file "$MIGRATE_DIR" "$json"
        else
            echo "$json import err, Abort."
            exit 1
        fi
    fi
done