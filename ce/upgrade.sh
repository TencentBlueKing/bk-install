#!/usr/bin/env bash
# Description: upgrade blueking module minor version release

set -euo pipefail
SELF_DIR=$(dirname "$(readlink -f "$0")")

# 加载load_env和通用函数
source "${SELF_DIR}"/tools.sh

BK_PKG_SRC_PATH=${BK_PKG_SRC_PATH:-/data/src}
BK_HOME=${BK_HOME:-/data/bkee}
PCMD=${SELF_DIR}/pcmd.sh 
# pcmd执行命令时限制为并发数1，串行更新
export PCMD_PARALLEL_NUMBER=1
# 默认对sync.sh启用rsync --delete的参数，如果需要取消，可以单独设置PRSYNC_EXTRA_OPTS=
export PRSYNC_EXTRA_OPTS="--delete"

usage () {
    echo "$0 <module>"
    exit 1
}

MODULE="$1"
MODULE_DIR_NAME=$(map_module_name $MODULE)
shift $(($# > 0 ? 0 : 1))

# check
if [[ -z "$MODULE_DIR_NAME" ]]; then
    echo "$MODULE 暂不支持通过本脚本更新"
    exit 1
fi
if ! [[ -e $BK_PKG_SRC_PATH/$MODULE_DIR_NAME ]]; then
    echo "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME 不存在，请确认蓝鲸正确安装了，且$HOME/.bkrc中存在正确的BK_PKG_SRC_PATH定义"
    exit 1
fi
if ! [[ -e $BK_HOME ]]; then
    echo "$BK_HOME不存在，请确认蓝鲸正确安装了，且$HOME/.bkrc中存在正确的BK_HOME定义"
    exit 1
fi

case "$MODULE" in
    paas|gse)
        # 从中控机同步到对应模块的目录
        emphasize "sync $MODULE to remote hosts"
        "$SELF_DIR"/sync.sh "$MODULE" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"

        # 远程调用release脚本更新
        emphasize "start upgade $MODULE"
        $PCMD -m "$MODULE" "$CTRL_DIR/bin/release_${MODULE}.sh -u -p $BK_HOME -s $BK_PKG_SRC_PATH -B $BK_PKG_SRC_PATH/backup -e $CTRL_DIR/bin/04-final/${MODULE}.env"
        if [[ "${MODULE}" =~ paas ]]; then
            bkiam_migrate "${MODULE#bk}"
        fi
        _update_common_info "${MODULE}"
        ;;
    cmdb)
        # 从中控机同步到对应模块的目录
        emphasize "sync $MODULE to remote hosts"
        "$SELF_DIR"/sync.sh "$MODULE" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"

        # 远程调用release脚本更新
        emphasize "start upgade $MODULE"
        $PCMD -p 1 -m "$MODULE" "$CTRL_DIR/bin/release_${MODULE}.sh -u -p $BK_HOME -s $BK_PKG_SRC_PATH -B $BK_PKG_SRC_PATH/backup -e $CTRL_DIR/bin/04-final/${MODULE}.env"
        _update_common_info "${MODULE}"
        ;;
    bkiam|bkssm|bkauth)
        emphasize "sync $MODULE to remote hosts"
        "$SELF_DIR"/sync.sh "${MODULE#bk}" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"

        # 导入sql文件
        "$SELF_DIR"/bin/sql_migrate.sh -n "mysql-${MODULE#bk}" "$BK_PKG_SRC_PATH/$MODULE"/support-files/sql/*.sql 

        # 远程调用install脚本更新
        emphasize "start upgade $MODULE"
        $PCMD -m "${MODULE#bk}" "$CTRL_DIR/bin/install_${MODULE}.sh -b \$LAN_IP -s ${BK_PKG_SRC_PATH}/ -p ${BK_HOME} -e ${CTRL_DIR}/bin/04-final/$MODULE.env"

        # 重启进程
        "${CTRL_DIR}"/control.sh restart "$MODULE"
        _update_common_info "${MODULE}"
        ;;
    bkiam_search_engine|iam_search_engine)
        emphasize "sync $MODULE to remote hosts"
        "$SELF_DIR"/sync.sh "${MODULE#bk}" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"

        # 远程调用install脚本更新
        emphasize "start upgade $MODULE"
        $PCMD -m "${MODULE#bk}" "$CTRL_DIR/bin/install_bkiam_search_engine.sh -b \$LAN_IP -s ${BK_PKG_SRC_PATH}/ -p ${BK_HOME} -e ${CTRL_DIR}/bin/04-final/$MODULE.env"

        # 重启进程
        ${CTRL_DIR}/control.sh restart "$MODULE"
        _update_common_info "${MODULE}"
        ;;
    appo|appt)
        emphasize "sync $BK_PKG_SRC_PATH/paas_agent/ to module: $1" 
        "${SELF_DIR}"/sync.sh "$MODULE" "$BK_PKG_SRC_PATH/paas_agent/" "$BK_PKG_SRC_PATH/paas_agent/"
        emphasize "sync $BK_PKG_SRC_PATH/image/ to module: $1" 
        "${SELF_DIR}"/sync.sh "$MODULE" "$BK_PKG_SRC_PATH/image/" "$BK_PKG_SRC_PATH/image/"

        # 远程调用release脚本更新
        emphasize "start upgade $MODULE"
        $PCMD -m "${MODULE#bk}" "$CTRL_DIR/bin/release_paasagent.sh -b \$LAN_IP -s ${BK_PKG_SRC_PATH}/ -p ${BK_HOME} -e ${CTRL_DIR}/bin/04-final/paasagent.env"
        ;;
    job)
        # 同步前端
        emphasize "sync job(frontend) to nginx hosts"
        "$SELF_DIR"/sync.sh nginx "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"
        # 同步后端
        emphasize "sync job(backend) to all job hosts"
        "$SELF_DIR"/sync.sh job "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"
        # 导入sql文件
        emphasize "import sql"
        "$SELF_DIR"/bin/sql_migrate.sh -n mysql-job "$BK_PKG_SRC_PATH"/job/support-files/sql/*/*.sql 
        # 更新权限模型
        bkiam_migrate job
        # 更新后端
        emphasize "update job backend on all job hosts"
        $PCMD -m job "$CTRL_DIR/bin/release_job_backend.sh -u -p $BK_HOME -s $BK_PKG_SRC_PATH -B $BK_PKG_SRC_PATH/backup -e $CTRL_DIR/bin/04-final/${MODULE}.env --run-mode ${BK_JOB_RUN_MODE}"
        # 更新前端
        emphasize "update job frontend on nginx hosts"
        $PCMD -m nginx "$CTRL_DIR/bin/release_job_frontend.sh -p $BK_HOME -s $BK_PKG_SRC_PATH -B $BK_PKG_SRC_PATH/backup -i \$BK_JOB_API_PUBLIC_URL"
        _update_common_info "${MODULE}"
        ;;
    usermgr|bknodeman|bklog|fta)
        emphasize "sync $MODULE to remote hosts"
        "$SELF_DIR"/sync.sh "${MODULE#bk}" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"
        emphasize "update $MODULE on all $MODULE hosts"
        $PCMD -m "${MODULE#bk}" "$CTRL_DIR/bin/release_${MODULE}.sh -u -p $BK_HOME -s $BK_PKG_SRC_PATH -B $BK_PKG_SRC_PATH/backup -e $CTRL_DIR/bin/04-final/${MODULE}.env"
        if [[ "${MODULE}" =~ "usermgr"  ]]; then
            bkiam_migrate "${MODULE#bk}"
        fi
        if [[ "${MODULE}" =~ "bknodeman"  ]]; then
            # 更新后刷新nginx上的脚本
            $PCMD -H "${BK_NODEMAN_IP}" 'docker exec -i bk-nodeman-nodeman runuser -u blueking ./bin/manage.sh copy_file_to_nginx'
        fi
        _update_common_info "${MODULE}"
        ;;
    bkmonitorv3|monitorv3)
        emphasize "sync $MODULE to remote hosts"
        "$SELF_DIR"/sync.sh "${MODULE#bk}" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"

        emphasize "migrate $MODULE sql"
        "$SELF_DIR"/bin/sql_migrate.sh -n mysql-default "$BK_PKG_SRC_PATH"/"$MODULE_DIR_NAME"/support-files/sql/*.sql
        
        emphasize "update $MODULE on all $MODULE hosts"
        $PCMD -m "${MODULE#bk}" "$CTRL_DIR/bin/release_${MODULE}.sh -u -p $BK_HOME -s $BK_PKG_SRC_PATH -B $BK_PKG_SRC_PATH/backup -e $CTRL_DIR/bin/04-final/$MODULE_DIR_NAME.env -M $BK_MONITOR_RUN_MODE"
        _update_common_info "${MODULE}"
        ;;
    cert)
        "${SELF_DIR}"/bkcli sync cert
        "${SELF_DIR}"/bkcli install cert
        emphasize "start upgade $MODULE"
        $PCMD -m "job" "$CTRL_DIR/bin/release_cert.sh -p $BK_HOME -e $CTRL_DIR/bin/04-final/job.env -j"
        "${SELF_DIR}"/bin/release_cert.sh -p "${BK_HOME}" -e "${SELF_DIR}"/bin/04-final/job.env
        ;;
    lesscode)
        emphasize "sync lesscode to lesscode host"
        "$CTRL_DIR"/sync.sh lesscode "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"
        emphasize "import sql"
        "$CTRL_DIR"/bin/sql_migrate.sh -n mysql-default "$BK_PKG_SRC_PATH"/"$MODULE_DIR_NAME"/support-files/sql/*.sql
        emphasize "start upgade $MODULE"
        $PCMD -m lesscode "$CTRL_DIR/bin/release_lesscode.sh -u -p $BK_HOME -s $BK_PKG_SRC_PATH -B $BK_PKG_SRC_PATH/backup -e $CTRL_DIR/bin/04-final/${MODULE}.env"
        ;;
    apigw|bkapigw)
        emphasize "update apigw frontend on host: ${BK_NGINX_IP_COMMA}"
        PRSYNC_EXTRA_OPTS="--delete" "${SELF_DIR}"/sync.sh nginx "${BK_PKG_SRC_PATH}/bk_apigateway/dashboard-fe/" "${INSTALL_PATH}/bk_apigateway/dashboard-fe/"
        "${SELF_DIR}"/pcmd.sh -m nginx "${CTRL_DIR}/bin/render_tpl -p ${INSTALL_PATH} -m bk_apigateway -e ${CTRL_DIR}/bin/04-final/bkapigw.env ${BK_PKG_SRC_PATH}/bk_apigateway/support-files/templates/dashboard-fe#static#runtime#runtime.js"

        emphasize "sync $MODULE to remote hosts"
        "$SELF_DIR"/sync.sh "${MODULE#bk}" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/" "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME/"

        # 导入sql文件
        emphasize "migrate $MODULE sql"
        "$SELF_DIR"/bin/sql_migrate.sh -n mysql-default "$BK_PKG_SRC_PATH"/"$MODULE_DIR_NAME"/support-files/sql/*.sql

        emphasize "update $MODULE on all $MODULE hosts"
        $PCMD -m "${MODULE#bk}" "$CTRL_DIR/bin/release_apigw.sh -u -p $BK_HOME -s $BK_PKG_SRC_PATH -B $BK_PKG_SRC_PATH/backup -e $CTRL_DIR/bin/04-final/bkapigw.env"
        ;;

    *) usage ;;
esac
