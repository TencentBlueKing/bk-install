#!/usr/bin/env bash
# 用途： 安装蓝鲸的CMDB平台后台
 
# 安全模式
set -euo pipefail 

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
# 默认的绑定端口
declare -A PROJECTS=(
    [cmdb-admin]=cmdb_adminserver
    [cmdb-api]=cmdb_apiserver
    [cmdb-auth]=cmdb_authserver
    [cmdb-cloud]=cmdb_cloudserver
    [cmdb-core]=cmdb_coreservice
    [cmdb-datacollection]=cmdb_datacollection
    [cmdb-event]=cmdb_eventserver
    [cmdb-host]=cmdb_hostserver
    [cmdb-operation]=cmdb_operationserver
    [cmdb-synchronize]=cmdb_synchronizeserver
    [cmdb-proc]=cmdb_procserver
    [cmdb-task]=cmdb_taskserver
    [cmdb-topo]=cmdb_toposerver
    [cmdb-web]=cmdb_webserver
    [cmdb-cache]=cmdb_cacheservice
)

declare -A PORTS=(
    [cmdb-admin]=9000
    [cmdb-api]=9001
    [cmdb-auth]=9002
    [cmdb-cloud]=9003
    [cmdb-core]=9004
    [cmdb-datacollection]=9005
    [cmdb-event]=9006
    [cmdb-host]=9007
    [cmdb-operation]=9008
    [cmdb-proc]=9009
    [cmdb-synchronize]=9010
    [cmdb-task]=9011
    [cmdb-topo]=9012
    [cmdb-web]=9013
    [cmdb-cache]=9014
)
declare -a MODULES=(${!PORTS[@]})

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

MODULE=cmdb

ENV_FILE=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -m, --module      [可选] "安装的子模块(${MODULES[*]}), 默认都会安装" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]

            [ -s, --srcdir      [必填] "从该目录拷贝cmdb目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ -l, --log-dir     [可选] "日志目录,默认为$PREFIX/logs/cmdb" ]

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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/cmdb}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/cmdb ]]; then
    warning "$MODULE_SRC_DIR/cmdb 不存在"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    useradd -m -d /home/blueking -c "BlueKing EE User" --shell /bin/bash blueking 

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env 
install -o blueking -g blueking -m 755 -d "$PREFIX/cmdb"
install -o blueking -g blueking -m 755 -d /var/run/cmdb

# 配置/var/run临时目录重启后继续生效
cat > /etc/tmpfiles.d/cmdb.conf <<EOF
D /var/run/cmdb 0755 blueking blueking
EOF

# 拷贝模块目录到$PREFIX
rsync -a --delete "${MODULE_SRC_DIR}"/cmdb/ "$PREFIX/cmdb/"

# 渲染配置
"$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
    -e "$ENV_FILE" \
    "$MODULE_SRC_DIR"/$MODULE/support-files/templates/server*.yaml

# 加载配置
source "$ENV_FILE"

cat <<EOF > /usr/lib/systemd/system/bk-cmdb.target
[Unit]
Description=Bk cmdb target to allow start/stop all bk-cmdb-*.service at once

[Install]
WantedBy=multi-user.target blueking.target
EOF

cat <<EOF > /etc/sysconfig/bk-cmdb
# log directory
BK_CMDB_LOG_DIR=$LOG_DIR
# other options
OPTS="--logtostderr=false --v=3 --regdiscv=$BK_CMDB_ZK_ADDR"
EOF

for m in "${!PROJECTS[@]}"; do
    binary=${PROJECTS[$m]}
    cat <<EOF > /etc/sysconfig/bk-${m}
PORT=${PORTS[$m]}
EOF
    cat <<EOF > /usr/lib/systemd/system/bk-${m}.service
[Unit]
Description=BlueKing CMDB($m) Server
After=network-online.target
PartOf=bk-cmdb.target

[Service]
User=blueking
Group=blueking
WorkingDirectory=/var/run/cmdb
EnvironmentFile=/etc/blueking/env/local.env
EnvironmentFile=/etc/sysconfig/bk-cmdb
EnvironmentFile=/etc/sysconfig/bk-$m
ExecStart=${PREFIX}/cmdb/server/bin/$binary --addrport=\${LAN_IP}:\${PORT} --log-dir=\${BK_CMDB_LOG_DIR} \$OPTS
Restart=always
RestartSec=3s
LimitNOFILE=204800
LimitCORE=infinity

[Install]
WantedBy=bk-cmdb.target
EOF
done

# cmdb-synchronize 默认不启动，所以要去掉partof=bk-cmdb.target
[[ -r /usr/lib/systemd/system/bk-cmdb-synchronize.service ]] &&  sed -i '/^PartOf/d' /usr/lib/systemd/system/bk-cmdb-synchronize.service 

# cmdb-admin
sed -i '/OPTS/d' /etc/sysconfig/bk-cmdb-admin
echo "OPTS=\"--logtostderr=false --v=3 --config=${PREFIX}/cmdb/server/conf/migrate.yaml\"" >> /etc/sysconfig/bk-cmdb-admin

# cmdb-cloud，默认不开启加密
sed -i '/OPTS/d' /etc/sysconfig/bk-cmdb-cloud
echo "OPTS=\"--logtostderr=false --v=3 --regdiscv=${BK_CMDB_ZK_ADDR} --enable_cryptor=false\"" >> /etc/sysconfig/bk-cmdb-cloud


# generate rsyslog.d/bk-cmdb.conf 
> /etc/rsyslog.d/bk-cmdb.conf
for m in "${!PROJECTS[@]}"; do
    binary=${PROJECTS[$m]}
    cat >> /etc/rsyslog.d/bk-cmdb.conf <<EOF
if \$programname == '$binary' then {
    action(
        type="omfile"
        FileCreateMode="0644"
        FileGroup="blueking"
        FileOwner="blueking"
        file="$LOG_DIR/$binary.stdout.log"
    )
    stop
}

EOF
done

# generate logrotate
cat > /etc/logrotate.d/bk-cmdb <<EOF
$LOG_DIR/*.stdout.log {
    daily
    missingok
    rotate 7
    compress
    copytruncate
    notifempty
    create 644 blueking blueking
    sharedscripts
    postrotate
        /usr/bin/pkill -HUP rsyslog 2> /dev/null || true
    endscript
}
EOF
systemctl restart rsyslog

chown -R blueking.blueking "$PREFIX/cmdb" "$LOG_DIR"

systemctl daemon-reload
systemctl enable bk-cmdb.target
for m in "${!PROJECTS[@]}"; do
    if ! [[ $m == 'cmdb-synchronize' ]];then    # synchronize默认不启动
        if ! systemctl is-enabled "bk-${m}" &>/dev/null; then
            systemctl enable "bk-${m}"
        fi
    fi
done