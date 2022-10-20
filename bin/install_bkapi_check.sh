#!/usr/bin/env bash

set -euo pipefail
source "${CTRL_DIR}"/load_env.sh

# 通用脚本框架变量
PROGRAM=$(basename "$0")
SELF_DIR=$(dirname "$(readlink -f "$0")")
EXITCODE=0

# 模块安装的所在目录
PREFIX=/data/bkee

# 模块安装包的所在目录
MODULE_SRC_DIR=/data/src

# PYTHON目录
PYTHON_PATH=/opt/py36/bin/python

# 需要安装的模块
MODULE=bkapi_check

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ --python-path     [可选] "指定创建virtualenv时的python二进制路径" ]

            [ -s, --srcdir      [必选] "从该目录拷贝bkapi_check目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ -m, --module      [可选] "需要验证的API模块,默认为全部"]

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
        --python-path )
            shift
            PYTHON_PATH=$1
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -m | --module )
            shift
            API_MODULE=$1
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
if ! [[ -d "$MODULE_SRC_DIR"/${MODULE} ]]; then
    warning "$MODULE_SRC_DIR/${MODULE} 不存在"
fi

if ! [[ $($PYTHON_PATH --version 2>&1) = *Python* ]]; then
    warning "$PYTHON_PATH 不是一个合法的python二进制"
fi

if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; }

install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"

# 拷贝模块目录到 $PREFIX
rsync -a --delete --exclude=reports "${MODULE_SRC_DIR}/$MODULE/" "$PREFIX/$MODULE/"

# 安装虚拟环境和依赖包
"${SELF_DIR}"/install_py_venv_pkgs.sh -e -p "$PYTHON_PATH" \
-n "${MODULE}" \
-w "${PREFIX}/.envs" -a "$PREFIX/$MODULE/" \
-s "$PREFIX/$MODULE/support-files/pkgs" \
-r "$PREFIX/$MODULE/requirements.txt"
