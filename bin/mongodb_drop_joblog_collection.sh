#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# 安全模式
set -euo pipefail 

# 通用脚本框架变量
PROGRAM=$(basename "$0")

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")

# 加载环境变量
if [[ -r ${SELF_DIR}/../load_env.sh ]]; then
    source "${SELF_DIR}/../load_env.sh"
else
    echo "${SELF_DIR}/../load_env.sh 不存在" >&2
    exit 1
fi

# 用户传入需要保留多久，date 命令支持的日期表达
DATE_SPEC=""
# joblog 的 collection 名日期后缀格式
DATE_FORMAT="%Y_%m_%d"
# 模拟执行与否
DRY_RUN=false

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -n, --dry-run         [可选] 模拟执行，输出会删除的 collection 列表]
            [ -d, --date            [必选] date 命令支持的时间表达式，如果有空格需要用引号，例如 "one month ago" 表示一个月前
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -n | --dry-run )
            DRY_RUN=true
            ;;
        -d | --date )
            shift
            DATE_SPEC=$1
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

BEFORE_DATE=$(date -d "$DATE_SPEC" +$DATE_FORMAT)
if ! [[ $BEFORE_DATE =~ ^[0-9]{4}_[0-9]{2}_[0-9]{2}$ ]]; then
    echo "$DATE_SPEC is not valid"
    exit 1
fi
if ! [[ -f "$CTRL_DIR"/load_env.sh ]]; then
    echo "$CTRL_DIR/load_env.sh is not exists"
    exit 1
fi
if ! which mongo &>/dev/null; then
    echo "本机mongo 命令不存在，无法链接mongodb"
    exit 1
fi
# 加载mongodb链接串
source "$CTRL_DIR"/load_env.sh

# 生成 js 命令
cat <<'EOF' > /tmp/delete_job_outdate_collection.js
var fileCollectionNames = db.getCollectionNames().filter(function (collection) { return /^job_log_file/.test(collection) && collection < "job_log_file_"+beforeDate })
var scriptCollectionNames = db.getCollectionNames().filter(function (collection) { return /^job_log_script/.test(collection) && collection < "job_log_script_"+beforeDate })
EOF

if [[ $DRY_RUN = "false" ]]; then
    cat <<'EOF' >> /tmp/delete_job_outdate_collection.js
fileCollectionNames.forEach(function(c){print("dropping:" + c);db[c].drop();})
scriptCollectionNames.forEach(function(c){print("dropping:" + c);db[c].drop();})
EOF
else
    cat <<'EOF' >> /tmp/delete_job_outdate_collection.js
fileCollectionNames.forEach(function(c){print("dropping:" + c);})
scriptCollectionNames.forEach(function(c){print("dropping:" + c);})
EOF
fi

# 执行清理的js
mongo --quiet "$BK_JOB_LOGSVR_MONGODB_URI" --eval 'var beforeDate="'$BEFORE_DATE'"' /tmp/delete_job_outdate_collection.js
