#!/usr/bin/env bash
# 用途：更新蓝鲸证书

# 安全模式
set -euo pipefail 

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0
ENV_FILE=
UPDATE_JOB=0

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
    通用参数：
            [ -p, --prefix          [可选] "安装的目标路径，默认为${PREFIX}" ]
            [ -e, --env-file        [可选] "渲染配置文件时，使用该配置文件中定义的变量值来渲染" ]
            [ -j, --update-job      [可选] "渲染job证书选择项" ]
            [ -v, --version         [可选] "脚本版本号" ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo -e "\033[0;32m$@\033[0m"
}

error () {
    echo -e "\033[0;33m$@\033[0m" 1>&2
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
        -e | --env-file )
            shift
            ENV_FILE=$1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -j | --update-job)
            UPDATE_JOB=1
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
    shift $(($# == 0 ? 0 : 1))
done 

if [[ "${UPDATE_JOB}" == 1 ]]; then
    source "$ENV_FILE"  # 加载密码和证书路径的环境变量
    if ! [[ -f $BK_CERT_PATH/gse_job_api_client.p12 || -f $BK_CERT_PATH/job_server.p12 ]]; then
        error "请确认证书目录($BK_CERT_PATH)是否存在gse_job_api_client.p12和job_server.p12文件"
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
    exit $?
fi

"${SELF_DIR}"/../bkcli restart license
"${SELF_DIR}"/../bkcli restart appo
"${SELF_DIR}"/../bkcli render gse
"${SELF_DIR}"/../bkcli restart gse
"${SELF_DIR}"/../bkcli render job
"${SELF_DIR}"/../bkcli restart job

log  "更新证书动作执行完成"