#!/usr/bin/env bash
# install_nginx.sh ：安装，配置 nginx
# 参考文档：https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/
#          https://github.com/denji/nginx-tuning

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
OFFLINE_RPM_DIR=
NGINX_VERSION="1.16.1"

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -d, --rpm-dir [必选] "指定rpm包存放的目录" ]
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
        -d | --rpm-dir )
            shift
            OFFLINE_RPM_DIR=$1
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
if [[ ! -d "$OFFLINE_RPM_DIR" ]]; then
    warning "不存在 $OFFLINE_RPM_DIR 目录"
fi
IFS=" " read -r -a pkgs <<< "$(cd "$OFFLINE_RPM_DIR" && echo nginx*${NGINX_VERSION}*.rpm)"
if (( ${#pkgs[@]} == 0 )); then
    warning "$OFFLINE_RPM_DIR 中不存在nginx*${NGINX_VERSION}*rpm。"
fi
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 安装或者升级nginx
if [[ $( printf "%s\n" "${pkgs[@]/.rpm/}" | grep -c -Ff - <(rpm -qa) ) -eq 2 ]]; then
    log "nginx rpm already installed"
else
    for pkg in "$OFFLINE_RPM_DIR"/nginx*"${NGINX_VERSION}"*.rpm; do
        rpm -Uvh "$pkg" || warning "注意：安装$pkg可能失败，或者已经安装了。"
    done
fi

# 修改默认配置 **TODO** 拆分到额外脚本
if [[ -w /etc/nginx/nginx.conf ]]; then
    [[ -f /etc/nginx/nginx.conf.orig ]] || cp -a /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
    # 修改默认process number为cpu核数(auto)
    sed -i 's/^worker_processes.*/worker_processes auto;/' /etc/nginx/nginx.conf
    # 加载upload模块
    #sed -i '/ngx_http_upload_module.so/d' /etc/nginx/nginx.conf
    #sed -i '/^events /i load_module "modules/ngx_http_upload_module.so";' /etc/nginx/nginx.conf
    # 修改 http 层级的默认参数，用配置文件覆盖方式
    echo "client_max_body_size 2G;" > /etc/nginx/conf.d/blueking.conf
    echo "underscores_in_headers on;" >> /etc/nginx/conf.d/blueking.conf
fi
