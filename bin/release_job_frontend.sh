#!/usr/bin/env bash
# 用途：更新蓝鲸的作业平台前端静态资源

# 安全模式
set -euo pipefail 

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
MODULE=job
# 模块安装后所在的上一级目录
PREFIX=/data/bkee
# 蓝鲸产品包解压后存放的默认目录
MODULE_SRC_DIR=/data/src
# 如果使用tgz来更新，则从该目录来找tgz文件
RELEASE_DIR=/data/release
# 备份目录
BACKUP_DIR=/data/src/backup
# 更新模式（tgz|src）
RELEASE_TYPE=
# 如果使用tgz来更新，该文件的文件名
TGZ_NAME=
# Job的api网关的外网URL
JOB_API_GATEWAY_URL=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
    通用参数：
            [ -p, --prefix          [可选] "安装的目标路径，默认为${PREFIX}" ]
            [ -B, --backup-dir      [可选] "备份程序的目录，默认是$BACKUP_DIR" ]
            [ -i, --gateway-url     [必选] "前端访问后端api的完整URL路径" ]
            [ -v, --version         [可选] "脚本版本号" ]

    更新模式有两种:
    1. 使用tgz包更新，则需要指定以下参数：
            [ -d, --release-dir     [可选] "$MODULE安装包存放目录，默认是$RELEASE_DIR" ]
            [ -f, --filename        [必选] "安装包名，不带路径" ]
    
    2. 使用中控机解压后的$MODULE_SRC_DIR/{module} 来更新: 需要指定以下参数
            [ -s, --srcdir      [可选] "从该目录拷贝$MODULE/目录到--prefix指定的目录" ]
    
    如果以上三个参数都指定了，会以tgz包的参数优先使用，忽略-s指定的目录
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
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -B | --backup-dir)
            shift
            BACKUP_DIR=$1
            ;;
        -d | --release-dir)
            shift
            RELEASE_DIR=$1
            ;;
        -f | --filename)
            shift
            TGZ_NAME=$1
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        -i | --gateway-url)
            shift
            JOB_API_GATEWAY_URL=$1
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
    shift $(($# == 0 ? 0 : 1))
done 

check_exists () {
    local file=$1
    if ! [[ -e "$file" ]]; then
        warning "$file is not exists. please check"
    fi
}

# 首先需要确定是哪种模式更新
if [[ -n "$TGZ_NAME" ]]; then
    # 如果确定 $TGZ_NAME 变量，那么无论如何都优先用tgz包模式更新
    RELEASE_TYPE=tgz
    TGZ_NAME=${TGZ_NAME##*/}    # 兼容传入带前缀路径的包名
    TGZ_PATH=${RELEASE_DIR}/$TGZ_NAME
else
    RELEASE_TYPE=src
fi

### 文件/文件夹是否存在判断
# 通用的变量
for f in "$PREFIX" "$BACKUP_DIR"; do 
    check_exists "$f"
done
# 不同release模式的差异判断
if [[ $RELEASE_TYPE = tgz ]]; then 
    check_exists "$TGZ_PATH"
else
    check_exists "$MODULE_SRC_DIR"/$MODULE 
fi
if ! [[ $JOB_API_GATEWAY_URL =~ ^http ]]; then
    warning "$JOB_API_GATEWAY_URL is not valid, it must start with http/https"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 备份现网目录
if [[ -d "$PREFIX"/job/frontend ]]; then
    tar -czf "$BACKUP_DIR/job_frontend-$(date +%Y%m%d_%H%M%S).tgz" -C "$PREFIX" job/frontend
fi
# 更新文件
if [[ $RELEASE_TYPE = tgz ]]; then
    # 创建临时目录
    TMP_DIR=$(mktemp -d /tmp/bkrelease_${MODULE}_XXXXXX)
    trap 'rm -rf $TMP_DIR' EXIT

    tar -C "$TMP_DIR"/ -xf "$TGZ_PATH" job/frontend

    # 更新全局文件
    log "updating 全局文件 ..."
    rsync --delete -av "${TMP_DIR}"/job/frontend/ "$PREFIX"/job/frontend/
else
    rsync --delete -av "${MODULE_SRC_DIR}"/job/frontend/ "$PREFIX"/job/frontend/
fi

chown -R blueking.blueking "${PREFIX}"/job/frontend/

# 修改index.html配置的api地址
sed -i "s|{{JOB_API_GATEWAY_URL}}|$JOB_API_GATEWAY_URL|" "$PREFIX"/job/frontend/index.html
if ! grep -Fq "$JOB_API_GATEWAY_URL" "$PREFIX"/job/frontend/index.html 2>/dev/null; then
    echo "edit frontend/index.html failed"
    exit 1
fi