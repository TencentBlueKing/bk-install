#!/usr/bin/env bash
# 加载所有的环境变量到一个文件

# 通用脚本框架变量
OLD_PWD=$(pwd)
cd ${BASH_SOURCE%/*} 2>/dev/null

# 特殊处理 处理初次安装时报错
[[ -f /etc/blueking/env/local.env ]] || mkdir -p /etc/blueking/env/ && touch /etc/blueking/env/local.env

# 生成临时文件来存放中间运算
TMP_ENV_FILE=$(mktemp "/tmp/bk_all_XXXXX.env")

if ! [[ -s ./bin/02-dynamic/hosts.env ]]; then
    echo "$(pwd)/bin/02-dynamic/hosts.env 不存在,请先生成"
    return 1
fi
shopt -s nullglob
awk '!/^\s*[A-Z][A-Z0-9_]+=\s*$/' \
    ./bin/01-generate/*.env \
    ./bin/02-dynamic/*.env \
    ./bin/03-userdef/*.env \
    ./bin/04-final/*.env \
    /etc/blueking/env/local.env > "$TMP_ENV_FILE"
shopt -u nullglob

source "$TMP_ENV_FILE"
cd "$OLD_PWD"
[[ -f "${TMP_ENV_FILE}" ]] && rm -f "${TMP_ENV_FILE}"