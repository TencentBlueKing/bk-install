#!/usr/bin/env bash
# 用途： 安装蓝鲸的Job平台后台
 
# 安全模式
set -euo pipefail 

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")

# 默认的绑定端口
declare -a MODULES=(
    job-logsvr
    job-manage
    job-execute
    job-gateway
    job-crontab
    job-config
    job-backup
    job-analysis
)

# 每个微服务模块默认的jvm内存
declare -A JOB_MODULE_JVM_HEAP=(
    ["job-logsvr"]=512m
    ["job-manage"]=1g
    ["job-execute"]=1g
    ["job-gateway"]=512m
    ["job-crontab"]=512m
    ["job-config"]=256m
    ["job-backup"]=512m
    ["job-analysis"]=1g
)

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

MODULE=job

ENV_FILE=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -m, --module      [可选] "安装的子模块(${MODULES[*]}), 默认都会安装" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]
            [ -s, --srcdir      [必填] "从该目录拷贝open_paas/module目录到--prefix指定的目录" ]
            [ -p, --prefix          [可选] "安装的目标路径，默认为/data/bkee" ]
            [ -l, --log-dir         [可选] "日志目录,默认为$PREFIX/logs/open_paas" ]
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/job}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/job ]]; then
    warning "$MODULE_SRC_DIR/job 不存在"
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
install -o blueking -g blueking -m 755 -d "$PREFIX/job"
install -o blueking -g blueking -m 755 -d /var/run/job
install -o blueking -g blueking -m 755 -d "$PREFIX/public/job"  # 上传下载目录

# 拷贝模块目录到$PREFIX
rsync -a --delete "${MODULE_SRC_DIR}"/job "$PREFIX/" 

# 渲染配置
"$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
    -e "$ENV_FILE" \
    "$MODULE_SRC_DIR"/$MODULE/support-files/templates/\#etc#job#*

# 生成keystore, truststore
source "$ENV_FILE"  # 加载密码和证书路径的环境变量
if ! [[ -f $BK_CERT_PATH/gse_job_api_client.p12 || -f $BK_CERT_PATH/job_server.p12 ]]; then
    echo "请确认证书目录($BK_CERT_PATH)是否存在gse_job_api_client.p12和job_server.p12文件"
    exit 1
fi
rm -fv "$BK_CERT_PATH"/*.keystore "$BK_CERT_PATH"/*.truststore
keytool -importkeystore -v -srckeystore "$BK_CERT_PATH/gse_job_api_client.p12" \
        -srcstoretype pkcs12 \
        -destkeystore "$BK_CERT_PATH/gse_job_api_client.keystore" \
        -deststoretype jks \
        -srcstorepass "$BK_GSE_SSL_KEYSTORE_PASSWORD" \
        -deststorepass "$BK_GSE_SSL_KEYSTORE_PASSWORD" \
        -noprompt

keytool -importkeystore -v -srckeystore "$BK_CERT_PATH"/job_server.p12 \
        -srcstoretype pkcs12 \
        -destkeystore "$BK_CERT_PATH"/job_server.keystore \
        -deststoretype jks \
        -srcstorepass "$BK_JOB_GATEWAY_SERVER_SSL_KEYSTORE_PASSWORD" \
        -deststorepass "$BK_JOB_GATEWAY_SERVER_SSL_KEYSTORE_PASSWORD" \
        -noprompt

keytool -keystore "$BK_CERT_PATH"/gse_job_api_client.truststore \
        -alias ca -import -trustcacerts \
        -file "$BK_CERT_PATH"/gseca.crt \
        -storepass "$BK_GSE_SSL_KEYSTORE_PASSWORD" \
        -noprompt

keytool -keystore "$BK_CERT_PATH"/job_server.truststore \
        -alias ca -import -trustcacerts \
        -file "$BK_CERT_PATH"/job_ca.crt \
        -storepass "$BK_JOB_GATEWAY_SERVER_SSL_KEYSTORE_PASSWORD" \
        -noprompt

# 先生成bk-job.target
cat <<EOF > /usr/lib/systemd/system/bk-job.target
[Unit]
Description=Bk Job target to allow start/stop all bk-job-*.service at once

[Install]
WantedBy=multi-user.target blueking.target
EOF

for m in "${MODULES[@]}"; do
    short_m=${m//job-/}
    cat <<EOF > /etc/sysconfig/bk-${m}
SPRING_PROFILE="-Dspring.profiles.active=native,prod"
CONFIG_FILE="-Dspring.config.additional-location=file://${PREFIX}/etc/job/application-${short_m}.yml"
CONFIG_DIR="-DBK_JOB_CONFIG_DIR=${PREFIX}/etc/job"
LOG_DIR="-Djob.log.dir=${PREFIX}/logs/job"
BINARY=${PREFIX}/job/backend/${m}/${m}.jar
JAVA_OPTS="-Xms${JOB_MODULE_JVM_HEAP[$m]} -Xmx${JOB_MODULE_JVM_HEAP[$m]}"
EOF
    cat <<EOF > /usr/lib/systemd/system/bk-${m}.service
[Unit]
Description=bk-${m}.service
After=network-online.target
PartOf=bk-job.target

[Service]
User=blueking
EnvironmentFile=-/etc/sysconfig/bk-${m}
WorkingDirectory=${PREFIX}/job/backend/${m}
ExecStartPost=/bin/bash -c 'until [ \$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8500/v1/agent/health/service/name/${m}?pretty) == 200 ]; do echo "waiting ${m} online";sleep 1; done'
ExecStart=/usr/bin/java -server -Dfile.encoding=UTF-8 \$SPRING_PROFILE \$CONFIG_FILE \$LOG_DIR \$CONFIG_DIR \$JAVA_OPTS -jar \$BINARY
StandardOutput=journal
StandardError=journal
SuccessExitStatus=143
LimitNOFILE=204800
LimitCORE=infinity
TimeoutStopSec=60
TimeoutStartSec=180
Restart=always
RestartSec=3s

[Install]
WantedBy=bk-job.target
EOF
    # 启动依赖job-config的启动
    if [[ $m != job-config ]]; then
        sed -i '/WorkingDirectory/a ExecStartPre=/bin/bash -c "until host job-config.service.consul; do sleep 1; done"' /usr/lib/systemd/system/bk-${m}.service
    fi
done

# job-gateway需要开启access日志
sed -i '/^CONFIG_DIR=/d' /etc/sysconfig/bk-job-gateway
sed -i '/^CONFIG_FILE=/a CONFIG_DIR="-DBK_JOB_CONFIG_DIR='${PREFIX}'/etc/job -Dreactor.netty.http.server.accessLogEnabled=true"' /etc/sysconfig/bk-job-gateway

chown -R blueking.blueking "$PREFIX/job" "$LOG_DIR" "$PREFIX/etc/job"

systemctl daemon-reload
systemctl enable bk-job.target
for m in "${MODULES[@]}"; do
    if ! systemctl is-enabled "bk-${m}" &>/dev/null; then
        systemctl enable "bk-${m}"
    fi
done
