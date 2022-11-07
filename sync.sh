#!/usr/bin/env bash
# 用途：封装prsync

SELF_DIR=$(dirname "$(readlink -f "$0")")

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <模块> <源文件/源目录> <目标目录>"
    echo "       PRSYNC_EXTRA_OPTS=\"--delete\" $0  <模块> <源文件/源目录> <目标目录>"
    echo "PRSYNC_EXTRA_OPTS的参数会透传给prsync的-x参数，然后透传给rsync命令"
    exit 1
fi

# 封装prsync，同步文件
PRSYNC_OPTS=(-a -v -z)
PRSYNC_EXTRA_OPTS=${PRSYNC_EXTRA_OPTS:-""}
MODULE=${1^^}
SRC=$2
DEST_DIR=$3
LAST_LINE_NUM=7

TMP_LOG_DIR=$(mktemp -d /tmp/bk_prsync_XXXXX)

trap 'rm -rf $TMP_LOG_DIR' EXIT 

# 加载环境变量
source ${SELF_DIR}/load_env.sh

if [[ $MODULE = "ALL" ]]; then
    ARRAYNAME=ALL_IP
else
    ARRAYNAME=BK_${MODULE}_IP
fi
tmp=${ARRAYNAME}[@]

# 根据模块获取的IP如果为空，则输入的模块名没有匹配任何ip，应该报错返回
if [[ -z "${!tmp}" ]]; then
    echo "${MODULE,,} ip count is 0, please check spelling or install.config file"
    exit 1
fi

# 并行rsync的时候，要跳过本机IP，否则会造成source file vanished报错
DEST_HOST=( $(printf "%s\n" "${!tmp}" | grep -vwF "$LAN_IP") )

# 排除掉自身后，如果ip列表为空，说明无需同步，则直接返回0
if [[ ${#DEST_HOST[@]} -eq 0 ]]; then
    echo "${MODULE,,} ip contains only controller ip, ignore sync."
    exit 0
fi

# 如果环境变量有PRSYNC_EXTRA_OPTS的参数，则追加
if [[ -n "$PRSYNC_EXTRA_OPTS" ]]; then
    PRSYNC_OPTS+=(-x "$PRSYNC_EXTRA_OPTS")
fi

prsync -e "$TMP_LOG_DIR"/stderr -o "$TMP_LOG_DIR"/stdout "${PRSYNC_OPTS[@]}" -h <(printf "%s\n" "${DEST_HOST[@]}") "$SRC" "$DEST_DIR/"
ret=$?
if [[ $ret -ne 0 ]]; then
    shopt -s nullglob
    (
        cd $TMP_LOG_DIR/stderr 
        for f in *; do 
            awk '{print "STDERR" FILENAME": " $0}' "$f" | tail -${LAST_LINE_NUM}
        done
        cd $TMP_LOG_DIR/stdout 
        for f in *; do 
            awk '{print "STDOUT" FILENAME": " $0}' "$f" | tail -${LAST_LINE_NUM}
        done
    )
    exit "$ret"
fi