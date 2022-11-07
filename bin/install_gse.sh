#!/usr/bin/env bash
# 用途： 安装蓝鲸的管控平台后台
 
# 安全模式
set -euo pipefail 

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

MODULE=gse

ENV_FILE=

BIND_ADDR=
OUTER_IP=

declare -A PROJECTS=(
    [gse-dba]=gse_dba
    [gse-api]=gse_api
    [gse-task]=gse_task
    [gse-data]=gse_data
    [gse-procmgr]=gse_procmgr
    [gse-btsvr]=gse_btsvr
    [gse-alarm]=gse_alarm
    [gse-config]=gse_config
)

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -m, --module      [可选] "安装的子模块(${!PROJECTS[@]}, 默认都会安装" ]
            [ -e, --env-file    [必选] "使用该配置文件来渲染" ]
            [ -b, --bind        [必选] "监听的内网网卡地址" ]
            [ -w, --wanip       [可选] "GSE的外网地址" ]

            [ -s, --srcdir      [必填] "从该目录拷贝gse目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ -l, --log-dir     [可选] "日志目录,默认为$PREFIX/logs/gse" ]

            [ -v, --version     [可选] 查看脚本版本号 ]
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

fail () {
    echo "$@" 1>&2
    exit 1
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
        -b | --bind)
            shift
            BIND_ADDR="$1"
            ;;
        -w | --wanip)
            shift
            OUTER_IP="$1"
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -l | --log-dir )
            shift
            LOG_DIR=$1
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/gse}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/gse ]]; then
    warning "$MODULE_SRC_DIR/gse 不存在"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if [[ -z "$BIND_ADDR" ]]; then
    warning "-b --bind参数必须指定"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装用户和配置目录
install -o root -g root -d "${LOG_DIR}"
install -o root -g root -m 755 -d "$PREFIX/gse"
install -o root -g root -m 755 -d /var/run/gse

# 拷贝模块目录(排除agent)到$PREFIX
rsync -av --delete --exclude="agent_*" --exclude=proxy "${MODULE_SRC_DIR}"/gse/ "$PREFIX/gse/"

# 渲染配置
"$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
    -e "$ENV_FILE" -E LAN_IP="$BIND_ADDR" -E WAN_IP="$OUTER_IP" \
    "$MODULE_SRC_DIR"/$MODULE/support-files/templates/#etc#*

# 先生成bk-gse.target
cat <<EOF > /usr/lib/systemd/system/bk-gse.target
[Unit]
Description=Bk gse target to allow start/stop all gse-*.service at once

[Install]
WantedBy=multi-user.target blueking.target
EOF
systemctl -q enable bk-gse.target

for m in "${!PROJECTS[@]}"; do
    binary=${PROJECTS[$m]}
    short_m=${m/gse-/}
    cat <<EOF > /usr/lib/systemd/system/bk-${m}.service
[Unit]
Description=GSE($short_m) Service
After=network-online.target
PartOf=bk-gse.target

[Service]
Type=forking
WorkingDirectory=/var/run/gse
ExecStart=$PREFIX/gse/server/bin/${binary} -f $PREFIX/etc/gse/${short_m}.conf
ExecStop=$PREFIX/gse/server/bin/${binary} --quit
ExecReload=/usr/bin/kill -36 \$MAINPID
PIDFile=/var/run/gse/run/${short_m}.pid
Restart=always
RestartSec=3s
LimitNOFILE=102400
LimitCORE=infinity

[Install]
WantedBy=bk-gse.target

EOF
done

# 配置/var/run临时目录重启后继续生效
cat > /etc/tmpfiles.d/gse.conf <<EOF
D /var/run/gse/run 0755 root root
EOF

systemctl daemon-reload
systemctl enable bk-gse.target
for m in "${!PROJECTS[@]}"; do
    if ! systemctl is-enabled "bk-${m}" &>/dev/null; then
        systemctl -q enable "bk-${m}"
    fi
done