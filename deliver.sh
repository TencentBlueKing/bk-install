#!/usr/bin/env bash
# 用途：同步中控机的src到对应的目标

# 默认变量
BK_APPT_IP_COMMA=
BK_NFS_IP=()

# 安全模式
set -euo pipefail 

# 加载环境变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
source "${SELF_DIR}"/load_env.sh
source "${SELF_DIR}"/functions

# 判断
[[ -d ${BK_PKG_SRC_PATH}/cert ]] || { echo "${BK_PKG_SRC_PATH} is not as expected. no ${BK_PKG_SRC_PATH}/cert/ found"; exit 1; }
[[ -f ${CTRL_DIR}/install.config ]] || { echo "${CTRL_DIR} is not as expected. no $CTRL_DIR/install.config found"; exit 1; }

# 默认对sync.sh启用rsync --delete的参数，如果需要取消，可以单独设置PRSYNC_EXTRA_OPTS=
export PRSYNC_EXTRA_OPTS="--delete"

case $1 in 
    license|cmdb|gse|usermgr|fta) 
        emphasize "sync $BK_PKG_SRC_PATH/$1/ to module: $1" 
        "${SELF_DIR}"/sync.sh "$1" "$BK_PKG_SRC_PATH/$1/" "$BK_PKG_SRC_PATH/$1/"
        ;;
    paas_plugins)
        emphasize "sync $BK_PKG_SRC_PATH/$1/ to module: paas" 
        "${SELF_DIR}"/sync.sh "paas" "$BK_PKG_SRC_PATH/$1/" "$BK_PKG_SRC_PATH/$1/"
        emphasize "sync $BK_PKG_SRC_PATH/java8.tgz to module: paas"
        "${SELF_DIR}"/sync.sh "paas" "$BK_PKG_SRC_PATH/java8.tgz" "$BK_PKG_SRC_PATH/"
        emphasize "sync $BK_PKG_SRC_PATH/$1/ to module: appo" 
        "${SELF_DIR}"/sync.sh "appo" "$BK_PKG_SRC_PATH/$1/" "$BK_PKG_SRC_PATH/$1/"
        if [[ -n ${BK_APPT_IP_COMMA} ]]; then
            emphasize "sync $BK_PKG_SRC_PATH/$1/ to module: appt" 
            "${SELF_DIR}"/sync.sh "appt" "$BK_PKG_SRC_PATH/$1/" "$BK_PKG_SRC_PATH/$1/"
        fi
        ;;
    appo|appt)
        emphasize "sync $BK_PKG_SRC_PATH/paas_agent/ to module: $1" 
        "${SELF_DIR}"/sync.sh "$1" "$BK_PKG_SRC_PATH/paas_agent/" "$BK_PKG_SRC_PATH/paas_agent/"
        emphasize "sync $BK_PKG_SRC_PATH/image/ to module: $1" 
        "${SELF_DIR}"/sync.sh "$1" "$BK_PKG_SRC_PATH/image/" "$BK_PKG_SRC_PATH/image/"
        ;;
    bkmonitorv3|monitorv3)
        emphasize "sync $BK_PKG_SRC_PATH/bkmonitorv3/ to module: $1" 
        "${SELF_DIR}"/sync.sh "monitorv3" "$BK_PKG_SRC_PATH/bkmonitorv3/" "$BK_PKG_SRC_PATH/bkmonitorv3/"
        ;;
    job)
        # 同步到job后台服务器
        emphasize "sync $BK_PKG_SRC_PATH/${1}/ to module: job" 
        "${SELF_DIR}"/sync.sh job "$BK_PKG_SRC_PATH/job/" "$BK_PKG_SRC_PATH/job/"
        # 同步前端代码到nginx服务器
        emphasize "sync $BK_PKG_SRC_PATH/${1}/ to module: nginx" 
        "${SELF_DIR}"/sync.sh "nginx" "$BK_PKG_SRC_PATH/job/" "$BK_PKG_SRC_PATH/job/"
        # 同步java到job后台
        emphasize "sync $BK_PKG_SRC_PATH/java8.tgz to module: job" 
        "${SELF_DIR}"/sync.sh job "$BK_PKG_SRC_PATH/java8.tgz" "$BK_PKG_SRC_PATH/"
        ;;
    paas|open_paas)
        emphasize "sync $BK_PKG_SRC_PATH/open_paas/ to module: paas" 
        "${SELF_DIR}"/sync.sh "paas" "$BK_PKG_SRC_PATH/open_paas/" "$BK_PKG_SRC_PATH/open_paas/"
        emphasize "sync $BK_PKG_SRC_PATH/image/ to module: $1" 
        "${SELF_DIR}"/sync.sh "$1" "$BK_PKG_SRC_PATH/image/" "$BK_PKG_SRC_PATH/image/"
        # 对于nfs要特殊处理
        if [ "${#BK_NFS_IP[@]}" -ne 0 ];then 
            chown -R blueking.blueking "${BK_PKG_SRC_PATH}"/open_paas/paas/media
            chmod -R 1777 "${BK_PKG_SRC_PATH}"/open_paas/paas/media
            emphasize "sync $BK_PKG_SRC_PATH/open_paas/paas/media/ to module: nfs" 
            rsync -avz "$BK_PKG_SRC_PATH/open_paas/paas/media/" "${BK_NFS_IP[0]}:$BK_HOME/public/nfs/open_paas/"
        fi
        ;;
    bknodeman|nodeman)
        emphasize "sync $BK_PKG_SRC_PATH/bknodeman/ to module: nodeman" 
        "${SELF_DIR}"/sync.sh "nodeman" "$BK_PKG_SRC_PATH/bknodeman/" "$BK_PKG_SRC_PATH/bknodeman/"
        if [ "${#BK_NFS_IP[@]}" -ne 0 ];then 
            chown -R blueking.blueking "${BK_PKG_SRC_PATH}"/python/py*
            "${SELF_DIR}"/pcmd.sh -m nfs "install -o blueking -g blueking  -m 1777 -d $BK_HOME/public/nfs/nodeman/{download,export,upload} $BK_HOME/public/nfs/nodeman/upload/{0..9}"
        fi
        ;;
    bkiam|iam)
        emphasize "sync $BK_PKG_SRC_PATH/bkiam/ to module: iam" 
        "${SELF_DIR}"/sync.sh "iam" "$BK_PKG_SRC_PATH/bkiam/" "$BK_PKG_SRC_PATH/bkiam/"
        ;;
    bkiam_search_engine|iam_search_engine)
        emphasize "sync $BK_PKG_SRC_PATH/bkiam_search_engine/ to module: iam_search_engine" 
        "${SELF_DIR}"/sync.sh "iam_search_engine" "$BK_PKG_SRC_PATH/bkiam_search_engine/" "$BK_PKG_SRC_PATH/bkiam_search_engine/"
        ;;
    bklog|log)
        emphasize "sync $BK_PKG_SRC_PATH/bklog/ to module: log" 
        "${SELF_DIR}"/sync.sh "log" "$BK_PKG_SRC_PATH/bklog/" "$BK_PKG_SRC_PATH/bklog/"
        ;;
    bkssm|ssm)
        emphasize "sync $BK_PKG_SRC_PATH/bkssm/ to module: ssm" 
        "${SELF_DIR}"/sync.sh "ssm" "$BK_PKG_SRC_PATH/bkssm/" "$BK_PKG_SRC_PATH/bkssm/"
        ;;
    bkauth|auth)
        emphasize "sync $BK_PKG_SRC_PATH/bkauth/ to module: bkauth" 
        "${SELF_DIR}"/sync.sh "auth" "$BK_PKG_SRC_PATH/bkauth/" "$BK_PKG_SRC_PATH/bkauth/"
        ;;
    ci|bkrepo|codecc)  # 需要同步java, docker-ce及openresty使用bk-custom仓库安装.
        "${SELF_DIR}"/sync.sh "${1}" "$BK_PKG_SRC_PATH/${1}/" "$BK_PKG_SRC_PATH/${1}/"
        "${SELF_DIR}"/sync.sh "${1}" "$BK_PKG_SRC_PATH/java8.tgz" "$BK_PKG_SRC_PATH/"
        ;;
    lesscode)
        emphasize "sync $BK_PKG_SRC_PATH/lesscode/ to module: lesscode" 
        "${SELF_DIR}"/sync.sh "${1}" "$BK_PKG_SRC_PATH/${1}/" "$BK_PKG_SRC_PATH/${1}/"
        ;;
    cert)
        chown -R blueking.blueking "${BK_PKG_SRC_PATH}/cert/"
        "${SELF_DIR}"/pcmd.sh -m "ALL" "if ! [[ -d ${BK_PKG_SRC_PATH}/backup ]]; then mkdir -p ${BK_PKG_SRC_PATH}/backup; fi"
        "${SELF_DIR}"/pcmd.sh -m "ALL" "for DIR in cert etc public logs; do if [[ ! -d ${BK_HOME}/\$DIR ]]; then install -o blueking -g blueking -m 755 -d ${BK_HOME}/\$DIR;fi;done"
        emphasize "sync $BK_PKG_SRC_PATH/cert/ to module: all" 
        "${SELF_DIR}"/sync.sh "ALL" "${BK_PKG_SRC_PATH}"/cert/ "${BK_PKG_SRC_PATH}"/cert/
        ;;
    common)
        emphasize "sync ${CTRL_DIR}/ to module: all"
        pssh -h <(printf "%s\n" "${ALL_IP[@]}") -i -x "-T" -I <<EOF
        [[ -d ${CTRL_DIR} ]] || mkdir -p ${CTRL_DIR}
EOF
        "${SELF_DIR}"/sync.sh "ALL" "$CTRL_DIR/" "$CTRL_DIR/"
        ;;
    bkapi)
        emphasize "sync $BK_PKG_SRC_PATH/bkapi_check/ to module: nginx"
        "${SELF_DIR}"/sync.sh "nginx" "$BK_PKG_SRC_PATH/bkapi_check/" "$BK_PKG_SRC_PATH/bkapi_check/"
        ;;
    apigw)
        emphasize "sync $BK_PKG_SRC_PATH/bk_apigateway/ to module: apigw"
        "${SELF_DIR}"/sync.sh "apigw" "$BK_PKG_SRC_PATH/bk_apigateway/" "$BK_PKG_SRC_PATH/bk_apigateway/"
        "${SELF_DIR}"/sync.sh "nginx" "$BK_PKG_SRC_PATH/bk_apigateway/" "$BK_PKG_SRC_PATH/bk_apigateway/"
        ;;
    *)
        echo "$1 暂不支持"
        exit 1
        ;;
esac