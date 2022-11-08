#!/usr/bin/env bash
# install_openresty.sh ：安装，配置 openresty
# 参考文档：https://openresty.org/en/linux-packages.html 

set -euo pipefail

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
PREFIX=/data/bkee
OPENRESTY_VERSION=1.15.8.3

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -p, --prefix ]   [必选] "指定蓝鲸的安装目录，默认为/data/bkee" ]
            [ -d, --config-dir [必选] "指定openresty的配置模板存放的目录" ]
            [ -v, --version    [可选] 查看脚本版本号 ]
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
        -d | --config-dir )
            shift
            CONFIG_DIR=$1
            ;;
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

if [[ ! -d $CONFIG_DIR ]]; then
    warning "$CONFIG_DIR 不存在"
fi
if ! id -u blueking &>/dev/null; then
    warning "blueking账户不存在"
fi
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 安装openresty 如果未安装过
yum -y install openresty-${OPENRESTY_VERSION}

# 配置openresty符合蓝鲸需要
install -d /usr/local/openresty/nginx/conf/conf.d

# 创建nginx logs目录
install -m 755 -o blueking -g blueking -d "$PREFIX"/logs/nginx

# 替换nginx.conf
sed 's,{{ key "bkcfg/global/bk_home" }},'$PREFIX',' "${SELF_DIR}"/../support-files/templates/nginx/nginx.conf > /usr/local/openresty/nginx/conf/nginx.conf
sed 's,{{ key "bkcfg/global/bk_home" }},'$PREFIX',' "${SELF_DIR}"/../support-files/templates/nginx/bk.ssl > /usr/local/openresty/nginx/conf/bk.ssl

# 生成lograte滚动日志
if ! [[ -f /etc/logrotate.d/nginx ]]; then
    cat <<EOF > /etc/logrotate.d/nginx
${PREFIX}/logs/nginx/*log {
    create 0644 blueking blueking
    daily
    rotate 10
    missingok
    notifempty
    compress
    sharedscripts
    postrotate
        /bin/kill -USR1 \`cat /usr/local/openresty/nginx/logs/nginx.pid 2>/dev/null\` 2>/dev/null || true
    endscript
}
EOF
fi

# 启动openresty
systemctl enable --now openresty
systemctl status openresty