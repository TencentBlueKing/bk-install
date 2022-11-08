#!/usr/bin/env bash
# 用途：安装和更新蓝鲸的bkiam，权限中心后台
# checker: 整个环境下只能只有一个，worker：整个环境下不超过 9 个


set -euo pipefail

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 默认部署模块
MODULE=

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
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -e, --envfile     [必填] "以该环境变量文件渲染配置" ]
            [ -b, --bind        [可选] "监听的网卡地址,默认为127.0.0.1" ]
            [ -m, --module      [必填] "需要部署的模块"]

            [ -s, --srcdir      [必填] "从该目录拷贝bkiam/目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ -l, --log-dir     [可选] "日志目录,默认为$PREFIX/logs/bkiam" ]

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
        -m | --module)
            shift
            MODULE=$1
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/bkiam}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR" ]]; then
    warning "$MODULE_SRC_DIR 不存在"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; }

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env

# 拷贝模块目录到$PREFIX
rsync -a "$MODULE_SRC_DIR/bkiam" "$PREFIX/" || error "安装模块(bkiam)失败"
chown -R blueking.blueking "$PREFIX/bkiam"

# 生成环境变量配置文件
"$SELF_DIR"/render_tpl -u -e "$ENV_FILE" -E LAN_IP="$BIND_ADDR" -m bkiam -p "$PREFIX" \
    "$MODULE_SRC_DIR/bkiam/support-files/templates/#etc#bkiam_config.yaml"

# 先生成bk-iam.target
cat <<EOF > /usr/lib/systemd/system/bk-iam.target
[Unit]
Description=Bk iam target to allow start/stop all bk-iam*.service at once

[Install]
WantedBy=multi-user.target blueking.target
EOF

# 生成service文件
case $MODULE in
    bk-iam)
        cat > /usr/lib/systemd/system/bk-iam.service <<EOF
[Unit]
Description="Blueking iam server"
After=network-online.target
PartOf=bk-iam.target

[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/bkiam/bin/iam -c $PREFIX/etc/bkiam_config.yaml
KillMode=process
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy= bk-iam.target
EOF
    ;;
    bk-iam-worker)
        cat > /usr/lib/systemd/system/bk-iam-worker@.service <<EOF
[Unit]
Description="Blueking iam %i server"
After=network-online.target
PartOf=bk-iam.target

[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/bkiam/bin/iam worker -c $PREFIX/etc/bkiam_config.yaml
KillMode=process
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=multi-user.target blueking.target bk-iam.target
EOF
    ;;
    bk-iam-checker)
        cat > /usr/lib/systemd/system/bk-iam-checker.service <<EOF
[Unit]
Description="Blueking iam checker server"
After=network-online.target
PartOf=bk-iam.target

[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/bkiam/bin/iam checker -c $PREFIX/etc/bkiam_config.yaml
KillMode=process
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=bk-iam.target
EOF
    ;;
    bk-iam-transfer)
        cat > /usr/lib/systemd/system/bk-iam-transfer.service <<EOF
[Unit]
Description="Blueking iam transfer server"
After=network-online.target
PartOf=bk-iam.target

[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/bkiam/bin/iam transfer -c $PREFIX/etc/bkiam_config.yaml
KillMode=process
Restart=always
RestartSec=3s
LimitNOFILE=204800

[Install]
WantedBy=bk-iam.target
EOF
    ;;

esac

systemctl daemon-reload
systemctl enable bk-iam.target
if [[ $MODULE == "bk-iam-worker" ]]; then
    if ! systemctl is-enabled bk-iam-worker@{worker1,worker2,worker3} &>/dev/null; then
        systemctl enable --now bk-iam-worker@{worker1,worker2,worker3}
    else
        systemctl start bk-iam-worker@{worker1,worker2,worker3}
    fi
else
    if ! systemctl is-enabled "$MODULE" &>/dev/null; then
        systemctl enable --now "$MODULE"
    else
        systemctl start "$MODULE"
    fi
fi

# 校验是否成功
sleep 1
systemctl status bk-iam*
