#!/usr/bin/env bash
# shellcheck disable=SC1090
# 用途：读取default/模块.env后，对于没有定义的变量，通过以下目录的对应文件的定义来merge生产最终的
#       模块所需要的全部环境变量

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")

MODULE="$1"

warning () {
    echo "$*" >&2
}

if [[ -z "$MODULE" ]]; then
    echo "Usage: $PROGRAM <模块名>"
    exit 
fi
# 生成临时文件来存放中间运算
TMP_GLOBAL_ENV_FILE=$(mktemp "/tmp/bk_global_XXXXX.env")
TMP_MODULE_ENV_FILE=$(mktemp "/tmp/bk.${MODULE}_XXXXX.env")

trap 'rm -f $TMP_GLOBAL_ENV_FILE' EXIT

# 首先要加载全局默认配置
# 过滤掉default中默认为空的变量（为空可能是以下几种：)
# 1. BK_XXX_PORT=$
# 2. BK_XXX_PORT=\s*$
# 3. BK_XXX_PORT=\s*#.*$ 
awk '!/^\s*[A-Z][A-Z0-9_]+=\s*(#.*)?$/' "$SELF_DIR"/default/*.env > "$TMP_GLOBAL_ENV_FILE"
source "$TMP_GLOBAL_ENV_FILE"

shopt -s nullglob   # 允许glob匹配为空
# 加载初次部署一次性生成的动态值，譬如密码，token等，这些值的文件不应该存在互相覆盖的问题
if [[ -d "$SELF_DIR/01-generate/" ]]; then
    for e in "${SELF_DIR}"/01-generate/*.env; do
        source "$e"
    done
fi

# 其次加载该模块的动态生成值（可重复更新的），目前只有全局的hosts.env文件生成
if [[ -d "$SELF_DIR/02-dynamic/" ]]; then
    for e in "${SELF_DIR}"/02-dynamic/"${MODULE}".*env; do
        source "$e"
    done
fi

# 最后加载该模块的用户自定义值
if [[ -r "$SELF_DIR/03-userdef/" ]]; then
    # 首先需要渲染自定义的global的全局配置
    if [[ -s "$SELF_DIR"/03-userdef/global.env ]]; then
        source "$SELF_DIR"/03-userdef/global.env  
    fi
    for e in "$SELF_DIR"/03-userdef/"${MODULE}".*env; do
        source "$e"
    done
fi

# 最终来把default中需要补全的变量都补全
{
    while read -r line || [[ -n "$line" ]]; do
        if [[ $line =~ ^[A-Z] ]]; then
            env_name=${line%%=*}
            printf "%s=%q\n" "${env_name}" "${!env_name}"
        else
            printf "%s\n" "$line"
        fi
    done < "$SELF_DIR/default/${MODULE}.env"
} > "$TMP_MODULE_ENV_FILE"


ret=0
# 检查必填参数为空
if grep -E "^\w+=('')?\$" "$TMP_MODULE_ENV_FILE"; then
    warning "检查以上输出的变量，请确保它们值不为空"
    ret=1
fi
# 覆盖final的env文件
cp "$TMP_MODULE_ENV_FILE" "${SELF_DIR}/04-final/${MODULE}.env" && rm -f "$TMP_MODULE_ENV_FILE"

exit "$ret"