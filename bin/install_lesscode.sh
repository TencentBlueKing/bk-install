#!/usr/bin/env bash
# 安装，配置lesscode
# 参考文档: https://github.com/Tencent/bk-PaaS/tree/lesscode-develop/paas-ce/lesscode#%E5%AE%89%E8%A3%85%E9%83%A8%E7%BD%B2

# 安全模式
set -euo pipefail 
# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
PREFIX=/data/src
MODULE_SRC_DIR=/data/src/
ENV_FILE=
MODULE=lesscode

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -j, --join            [必填] "集群的服务器列表，逗号分隔，请注意保持顺序，broker.id会自动根据ip出现的顺序来生成" ]
            [ -v, --version         [可选] "查看脚本版本号" ]
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
        -e | --env-file)
            shift
            ENV_FILE="$1"
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1 
            ;;
        -p |--prefix )
            shift
            PREFIX="$1"
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
if ! [[ -d "$MODULE_SRC_DIR"/lesscode ]]; then
    warning "$MODULE_SRC_DIR/lesscode 不存在"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 创建用户和配置目录
id -u blueking &>/dev/null || \
    useradd -m -d /home/blueking -c "BlueKing EE User" --shell /bin/bash blueking 
install -o blueking -g blueking -m 755 -d "$PREFIX/lesscode"
install -o blueking -g blueking -m 755 -d "$LOGS_PATH/lesscode"

rsync -a --delete "${MODULE_SRC_DIR}"/lesscode "$PREFIX/" 
chown -R blueking.blueking "${PREFIX}"/lesscode

cat > /usr/lib/systemd/system/bk-lesscode.service <<EOF
[Unit]
Description="Blueking Lesscode"
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
WorkingDirectory=${PREFIX}/lesscode
ExecStart=/usr/bin/node ${PREFIX}/lesscode/lib/server/app.browser.js
KillMode=process
Environment=NODE_ENV=production
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target
EOF

# 渲染配置
"$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
    -e "$ENV_FILE" \
    "$MODULE_SRC_DIR"/$MODULE/support-files/templates/*

# 进程启动
cd "${PREFIX}"/${MODULE} && npm install .
cd "${PREFIX}"/${MODULE} && npm run build
systemctl daemon-reload
systemctl enable bk-lesscode.service 