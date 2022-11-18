#!/usr/bin/env bash
# install_yum.sh ：安装，配置蓝鲸本地yum源

set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
PREFIX=/opt/yum
HTTP_PORT=8080
PYTHON_PATH=/usr/bin/python

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -p, --prefix ]         [必选] "指定源安装目录，默认为/opt/yum" ]
            [ -P, --http_port        [可选]  "为本地源提供http服务的端口" ]
            [ -python, --python-path [可选] "启动SimpleHTTPServer 所使用的解释器" ]
            [ -v, --version          [可选] 查看脚本版本号 ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo "$@"
}

check_port_alive () {
    local port=$1

    lsof -i:"$port" -sTCP:LISTEN 1>/dev/null 2>&1

    return $?
}

wait_port_alive () {
    local port=$1
    local timeout=${2:-10}

    for ((n=0; n<timeout; n++)); do
        check_port_alive "$port" && return 0
        sleep 1
    done
    return 1
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
        -P | --http_port )
            shift
            HTTP_PORT=$1
            ;;
        -python | --python-path)
            shift
            PYTHON_PATH=$1
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

# 检查 
if [[ ! -d $PREFIX ]]; then
    warning "$PREFIX 不存在"
fi

if lsof -i:"${HTTP_PORT}" | grep LISTEN >/dev/null;then 
    warning "端口：${HTTP_PORT} 已被占用"
fi

if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 开始安装
yum install -y createrepo || error "yum install craeterepo failed!"

chmod 644 -R "${PREFIX}"

cat > /usr/lib/systemd/system/bk-yum.service << EOF 
[Unit]
Description=Blueking Yum Repo
After=network-online.target
Wants=network-online.target

[Service]
User=root
Group=root

WorkingDirectory=${PREFIX}
ExecStart=${PYTHON_PATH} -m SimpleHTTPServer ${HTTP_PORT}
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

systemctl enable bk-yum.service --now

if ! createrepo "$PREFIX"; then
    echo "createrepo $PREFIX failed"
    exit 1
fi

if ! wait_port_alive "${HTTP_PORT}" 30; then
    echo "Python(SimpleHTTPServer) listen ${HTTP_PORT} failed"
    echo "please check output of <systemctl status bk-yum>"
    exit 1
fi
