#!/usr/bin/env bash

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
APISIX_VERSION="2.14.1"

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

MODULE=apisix

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -p, --prefix  [可选] "安装的目标路径，默认为$PREFIX"]
            [ -v, --version [可选] 查看脚本版本号 ]
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

# 解决 apisix nginx 编译路径写死的问题
ln -s "$PREFIX"/bk_apigateway/apisix/openresty /usr/local/openresty

# 生成 apisix systemd 托管文件
cat > /usr/lib/systemd/system/apisix.service << EOF
[Unit]
Description=apisix
#Conflicts=apisix.service
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=blueking
Group=blueking
PIDFile=$PREFIX/logs/bk_apigateway/$MODULE/logs/nginx.pid
WorkingDirectory=$PREFIX/bk_apigateway/apigateway/$MODULE
ExecStart=$PREFIX/bk_apigateway/$MODULE/$MODULE/apisix.sh start
ExecStop=$PREFIX/bk_apigateway/$MODULE/$MODULE/apisix.sh stop
ExecReload=$PREFIX/bk_apigateway/$MODULE/$MODULE/apisix.sh reload
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

if ! systemctl is-enabled "apisix.service" &>/dev/null; then
    systemctl enable "apisix.service"
fi

systemctl start "apisix.service"
