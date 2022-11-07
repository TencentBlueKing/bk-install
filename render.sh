#!/usr/bin/env bash
# 封装渲染配置的逻辑

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PCMD=${SELF_DIR}/pcmd.sh
RENDER_TOOL=${SELF_DIR}/bin/bkr.sh

usage () {
    echo "Usage: $0 <模块|主机IP串> <渲染的模块名>"
    echo "       第一个参数如果是模块名，那么第二个参数自动忽略等价于第一个参数。可以为paas,cmdb,usermgr,bkiam,bkssm等"
    echo "       第一个参数如果是主机IP串，可以为逗号分隔，那么第二个参数必须填待渲染的模块名"
    exit 2
}

if [[ $# -eq 1 ]]; then
    TARGET=$1
elif [[ $# -eq 2 ]]; then
    TARGET=$1
    MODULE=$2
else
    echo "参数个数不为1或2"
    usage
fi

if [[ $TARGET =~ ^[0-9.,]+ ]] && [[ -z "$MODULE" ]]; then
    echo "$1为ip串，但是没有传入第二个参数"
    usage
elif [[ $TARGET =~ ^[0-9.,]+ ]] && [[ -n "$MODULE" ]]; then
    echo "render $MODULE configuration for $TARGET"
    $PCMD -H "$TARGET" "${RENDER_TOOL} $MODULE" 
elif [[ $TARGET =~ ^[a-z][a-z0-9]+ ]]; then
    echo "render $TARGET configuration for $TARGET"
    # 为模块名
    $PCMD -m "${TARGET#bk}" "${RENDER_TOOL} $TARGET"
else
    echo "$TARGET 参数不合法"
    usage
fi