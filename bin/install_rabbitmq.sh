#!/usr/bin/env bash
# 用途：安装并配置rabbitmq
# 参考文档：- https://www.rabbitmq.com/install-rpm.html
#          - https://github.com/rabbitmq/erlang-rpm
#          - 配置文档：https://www.rabbitmq.com/configure.html
#          - 修改文件目录路径等：https://www.rabbitmq.com/relocate.html
#          - 生产环境配置checklist：https://www.rabbitmq.com/production-checklist.html

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
ADMIN_USER=
ADMIN_PASSWORD=
DATA_DIR=/var/lib/rabbitmq
LOG_DIR=/var/log/rabbitmq
RABBITMQ_VERSION="3.8.3"
NODE_NAME=rabbit@${HOSTNAME%%.*}.node.consul

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -n, --node-name   [选填] "部署的rabbitmq 节点名,如果包含period，则当作FQDN处理，默认为rabbit@\${HOSTNAME%%.*}.node.consul" ]
            [ -u, --user        [必填] "部署的rabbitmq 管理员用户名" ]
            [ -p, --password    [必填] "部署的rabbitmq 管理员密码" ]
            [ -d, --data-dir    [必填] "部署的rabbitmq 数据目录" ]
            [ -l, --log-dir     [必填] "部署的rabbitmq 日志目录" ]

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
        -u | --user )
            shift
            ADMIN_USER=$1
            ;;
        -p | --password )
            shift
            ADMIN_PASSWORD=$1
            ;;
        -n | --node-name )
            shift
            NODE_NAME=$1
            ;;
        -d | --data-dir)
            shift
            DATA_DIR="$1"
            ;;
        -l | --log-dir)
            shift
            LOG_DIR="$1"
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

if ! [[ $NODE_NAME =~ @ ]]; then
    warning "-n(--node-name) 应该包含 @，比如rabbit@bk-1.node.consul或者rabbit@rbtnode1"
fi

# 参数合法性有效性校验，这些可以使用通用函数校验。
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装依赖
if ! rpm -ql rabbitmq-server-${RABBITMQ_VERSION} &>/dev/null; then
    yum -q -y install socat || error "安装rabbitmq依赖的socat失败"
    yum -q -y install rabbitmq-server-${RABBITMQ_VERSION} || error "安装rabbitmq server${RABBITMQ_VERSION}失败"
fi

install -o rabbitmq -g rabbitmq -d "${LOG_DIR}"/
install -o rabbitmq -g rabbitmq -d "${DATA_DIR}"/

# 调整limits，根据：https://www.rabbitmq.com/configure.html#kernel-limits
install -d -m 755 -o root -g root /etc/systemd/system/rabbitmq-server.service.d/
echo '[Service]' > /etc/systemd/system/rabbitmq-server.service.d/limits.conf
echo 'LimitNOFILE=102400' >> /etc/systemd/system/rabbitmq-server.service.d/limits.conf

# 生成环境变量配置文件（主要用于重新定义各种路径）
cat <<EOF > /etc/rabbitmq/rabbitmq-env.conf
NODENAME=$NODE_NAME
MNESIA_BASE=${DATA_DIR}
LOG_BASE=${LOG_DIR}
EOF

# 配置系统的logrotate
cat <<EOF > /etc/logrotate.d/rabbitmq-server
$LOG_DIR/*.log {
    daily
    missingok
    rotate 14
    size 100M
    compress
    notifempty
    sharedscripts
    postrotate
        /bin/kill -SIGUSR1 \`cat $DATA_DIR/${NODE_NAME}.pid 2> /dev/null\` 2> /dev/null || true
    endscript
}
EOF

# 如果nodename包含period，那么增加USE_LONGNAME的参数
if [[ $NODE_NAME =~ \. ]]; then
    echo "USE_LONGNAME=true" >> /etc/rabbitmq/rabbitmq-env.conf 
fi

# 开启management的插件
rabbitmq-plugins --longnames --offline enable rabbitmq_management

# 启动rabbitmq-server
systemctl enable --now rabbitmq-server 

# 删除默认的guest用户
rabbitmqctl delete_user guest

# 增加管理员账户
rabbitmqctl add_user "$ADMIN_USER" "$ADMIN_PASSWORD"
rabbitmqctl set_user_tags "$ADMIN_USER" administrator
