#!/usr/bin/env bash
# 用途：初始化 bk-gse 网关数据

# 通用脚本框架变量
PROGRAM=$(basename "$0")
EXITCODE=0

# bk-gse 网关文档数据
BK_GSE_APIGW_DOCS_DIR=/data/docs/

GSE_APP_CODE=bk_gse
GSE_APP_SECRET=

BK_APIGW_NAME=bk-gse
BK_GSE_APP_VERSION=

IMAGES_NAME=bk-gse-apimgr
BK_API_URL_TMPL=

# bk-gse 接口权限授权
BK_GRANT_APP_CODE_LIST='[{"bk_app_code":"bk_job"},{"bk_app_code":"bk_nodeman"},{"bk_app_code":"bk_cmdb"},{"bk_app_code":"bk_monitorv3"},{"bk_app_code":"bk_log_search"},{"bk_app_code":"bk_bcs_app"},{"bk_app_code":"bk_sops"}]'

# 镜像仓库地址
IMAGE_REGISTRY=hub.bktencent.com/blueking

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -c, --code     [必填] "GSE 的 app code" ]
            [ -s, --secret   [必填] "GSE 的 secret" ]
            [ -v, --version  [必填] "初始化 $BK_APIGW_NAME 网关数据的 GSE 版本" ]
            [ -l, --url      [必填] "apigateway的 bkapi 地址" ]
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

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do
    case "$1" in
        -c | --code )
            shift
            GSE_APP_CODE=$1
            ;;
        -s | --secret )
            shift
            GSE_APP_SECRET=$1
            ;;
        -v | --version )
            shift
            BK_GSE_APP_VERSION=$1
            ;;
        -l | --url )
            shift
            BK_API_URL_TMPL=$1
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
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

if [[ -z "$GSE_APP_CODE" || -z "$GSE_APP_SECRET" || -z "$BK_GSE_APP_VERSION" || -z "$BK_API_URL_TMPL" ]]; then
    error "参数不满足要求，请根据提示传递需要参数"
fi

# 启动 bk-gse 初始化数据镜像
docker run --name=$IMAGES_NAME --net=host \
    --env BK_APIGW_NAME="$BK_APIGW_NAME" \
    --env BK_API_URL_TMPL="$BK_API_URL_TMPL/api/{api_name}" \
    --env BK_APP_CODE="$GSE_APP_CODE" \
    --env BK_APP_SECRET="$GSE_APP_SECRET" \
    --env BK_GRANT_APP_CODE_LIST="$BK_GRANT_APP_CODE_LIST" \
    --env BK_APIGW_RESOURCE_DOCS_BASE_DIR="$BK_GSE_APIGW_DOCS_DIR" \
    --env BK_GSE_PROC_HTTP_API=gse-procmgr.service.consul:52030 \
    --env BK_GSE_APP_VERSION="$BK_GSE_APP_VERSION"\
    --env BK_GSE_TASK_HTTP_API=gse-task.service.consul:28863 \
    --env BK_GSE_DATA_CFG_HTTP_API=gse-data.service.consul:59702 \
    --env BK_GSE_CLUSTER_HTTP_API=gse-cluster.service.consul:28808 \
    -d $IMAGE_REGISTRY/$IMAGES_NAME:"$BK_GSE_APP_VERSION"  sync-apigateway

# 查看日志
docker logs -f $IMAGES_NAME
