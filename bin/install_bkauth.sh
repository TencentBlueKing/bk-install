#!/usr/bin/env bash
# 用途：安装蓝鲸的 bkauth
#

set -euo pipefail

# 重置 PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
BIND_ADDR="127.0.0.1"
ENV_FILE=

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

usage () {
    cat <<EOF
用法:
    $PROGRAM [-h --help -?  查看帮助]
            [-e, --envfile     [必填] "以该环境变量文件渲染配置" ]
            [-b, --bind        [可选] "监听的网卡地址, 默认为 127.0.0.1" ]

            [-s, --srcdir      [必填] "从该目录拷贝 bkauth 目录到 --prefix 指定的目录" ]
            [-p, --prefix      [可选] "安装的目标路径，默认为 / data/bkee" ]
            [-l, --log-dir     [可选] "日志目录, 默认为 $PREFIX/logs/bkauth" ]

            [-v, --version     [可选] 查看脚本版本号 ]
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
(($# == 0)) && usage_and_exit 1
while (($#> 0 )); do
    case "$1" in
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -e | --envfile )
            shift
            ENV_FILE=$1
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/bkauth}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR" ]]; then
    warning "$MODULE_SRC_DIR 不存在"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if ((EXITCODE> 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; }

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env

# 拷贝模块目录到 $PREFIX
rsync -a "$MODULE_SRC_DIR/bkauth" "$PREFIX/" || error "安装模块 (bkauth) 失败"
chown -R blueking.blueking "$PREFIX/bkauth"

# 生成环境变量配置文件
"$SELF_DIR"/render_tpl -u -e "$ENV_FILE" -E LAN_IP="$BIND_ADDR" -m bkauth -p "$PREFIX" \
    "$MODULE_SRC_DIR/bkauth/support-files/templates/#etc#bkauth_config.yaml"

# 生成 service 文件
cat > /usr/lib/systemd/system/bk-auth.service <<EOF
[Unit]
Description="Blueking Auth Server"
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/bkauth/bin/bkauth -c $PREFIX/etc/bkauth_config.yaml
KillMode=process
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target
EOF

# 启动前需要先同步 open_paas 数据库旧数据
$PREFIX/bkauth/bin/bkauth sync -c $PREFIX/etc/bkauth_config.yaml

systemctl daemon-reload
if ! systemctl is-enabled "bk-auth" &>/dev/null; then
    systemctl enable --now bk-auth
else
    systemctl start bk-auth
fi

# 校验是否成功
sleep 1
systemctl status bk-auth