#!/usr/bin/env bash
# vim:ft=sh sts=4 ts=4 sw=4 expandtab nu ai
# set -euo pipefail
source "${CTRL_DIR}"/load_env.sh
source "${CTRL_DIR}"/functions
source "${CTRL_DIR}"/tools.sh
set -e

_initdata_mysql () {
    # 如果存在mysql(paas)则paas 只授权对应需要改独立mysql的用户登录, 否则为默认mysql
    source <(/opt/py36/bin/python ${CTRL_DIR}/qq.py -s -P ${CTRL_DIR}/bin/default/port.yaml)
    local grant_user_list=${_projects["mysql"]}
    # 第一步 对应模块授权对应的mysql  如果没有独有mysql则授权 default mysql
    for ip in "${BK_MYSQL_IP[@]}"; do
        for project in ${grant_user_list[@]}; do
            target=BK_MYSQL_${project^^}_IP_COMMA
            if [[ $project == 'monitorv3' ]]; then
                arraypaas=BK_MONITOR_MYSQL_PASSWORD
            elif [[ $project == 'job' ]]; then
                arraypaas=BK_JOB_MANAGE_MYSQL_PASSWORD
            elif [[ $project == 'log' ]]; then
                arraypaas=BK_BKLOG_MYSQL_PASSWORD
            else
                arraypaas=BK_${project^^}_MYSQL_PASSWORD
            fi
            mysql_user=${_project_name["mysql,${project}"]}
            if ! [[ -z ${!target} ]]; then
                login_path="${project}-root"
                emphasize "grant mysql privileges for ${mysql_user} by ${ip} login_path: ${login_path}"
                "${CTRL_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/grant_mysql_priv.sh -n ${login_path} -u ${mysql_user} -p '${!arraypaas}' -H ${ALL_IP_COMMA}"
                "${CTRL_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/grant_mysql_priv.sh -n ${login_path} -u root -p '${BK_MYSQL_ADMIN_PASSWORD}' -H ${ALL_IP_COMMA}"
            fi
            if ! grep "${ip}" "${CTRL_DIR}"/bin/02-dynamic/hosts.env | grep "BK_MYSQL_.*_IP_COMMA" >/dev/null; then
                login_path="default-root"
                emphasize "grant mysql privileges for ${mysql_user} by ${ip} login_path: ${login_path}"
                "${CTRL_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/grant_mysql_priv.sh -n ${login_path} -u ${mysql_user} -p '${!arraypaas}' -H  ${ALL_IP_COMMA}"
                "${CTRL_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/grant_mysql_priv.sh -n ${login_path} -u root -p '${BK_MYSQL_ADMIN_PASSWORD}' -H  ${ALL_IP_COMMA}"
            fi
        done
    done

    # 如果存在mysql(paas), 授权给所有模块访问
    if ! [[ -z "${BK_MYSQL_PAAS_IP_COMMA}" ]]; then
        for project in ${grant_user_list[@]}; do
            mysql_user=${_project_name["mysql,${project}"]}
            if [[ $project == 'monitorv3' ]]; then
                arraypaas=BK_MONITOR_MYSQL_PASSWORD
            elif [[ $project == 'job' ]]; then
                arraypaas=BK_JOB_MANAGE_MYSQL_PASSWORD
            else
                arraypaas=BK_${project^^}_MYSQL_PASSWORD
            fi
            login_path="paas-root"
            "${CTRL_DIR}"/pcmd.sh -H "${BK_MYSQL_PAAS_IP_COMMA}" "${CTRL_DIR}/bin/grant_mysql_priv.sh -n '${login_path}' -u '${mysql_user}' -p '${!arraypaas}' -H '${ALL_IP_COMMA}'"
            "${CTRL_DIR}"/pcmd.sh -H "${BK_MYSQL_PAAS_IP_COMMA}" "${CTRL_DIR}/bin/grant_mysql_priv.sh -n '${login_path}' -u root -p '${BK_MYSQL_ADMIN_PASSWORD}' -H '${ALL_IP_COMMA}'"
        done
    fi
}

_initdata_nodeman () {
    local ip=$BK_NODEMAN_IP0

    emphasize "clean up official_plugin old version packages"
    # 清理 GSE 缓存的包
    "${CTRL_DIR}"/pcmd.sh -H "$ip" " find ${INSTALL_PATH}/bknodeman/nodeman/official_plugin/gse_agent/ ${INSTALL_PATH}/bknodeman/nodeman/official_plugin/gse_proxy/ -type f -name gse_*[ce]e-*.tgz -exec rm -fv {} \;"

    emphasize "copy file to nginx"
    "${CTRL_DIR}"/pcmd.sh -H "$ip" "docker exec -i bk-nodeman-nodeman runuser -u blueking -- bash -lc './bin/manage.sh copy_file_to_nginx'"

    emphasize "copy gse file to nodeman"
    gse_server_pkg=$(_find_lastet_gse_server)
    gse_agent_pkg=$(_find_latest_gse_agent)
    rsync -av "${BK_PKG_SRC_PATH}"/{"$gse_server_pkg","$gse_agent_pkg"} "$ip":"${BK_PKG_SRC_PATH}"/

    # 将 gse_server gse_agent 包放入指定路径
    "${CTRL_DIR}"/pcmd.sh -H "$ip" "cp -a ${BK_PKG_SRC_PATH}/$gse_agent_pkg ${INSTALL_PATH}/bknodeman/nodeman/official_plugin/gse_agent/"
    "${CTRL_DIR}"/pcmd.sh -H "$ip" "cp -a ${BK_PKG_SRC_PATH}/$gse_server_pkg ${INSTALL_PATH}/bknodeman/nodeman/official_plugin/gse_proxy/"

    emphasize "start gse agent packaging, please wait for moment"
    "${CTRL_DIR}"/pcmd.sh -H "$ip" "docker exec -i bk-nodeman-nodeman runuser -u blueking -- bash -lc 'source bin/environ.sh; python manage.py init_agents -o stable'"
    
    emphasize "sync gse plugins to host: nodeman"
    chown -R blueking.blueking "${BK_PKG_SRC_PATH}"/gse_plugins/ 
    rsync -v "${BK_PKG_SRC_PATH}"/gse_plugins/*.tgz "$ip":"${INSTALL_PATH}"/bknodeman/nodeman/official_plugin/

    emphasize "init official plugins on host: nodeman"
    "${CTRL_DIR}"/pcmd.sh -H "$ip" "docker exec -i bk-nodeman-nodeman runuser -u blueking -- bash -lc 'rm -fv ./official_plugin/pluginscripts-*.tgz; ./bin/manage.sh init_official_plugins'"

    emphasize "sync py36.tgz file to host:nodeman"
    rsync -avz "${BK_PKG_SRC_PATH}"/python/py36.tgz "$ip":"${INSTALL_PATH}"/public/bknodeman/download/
    "${CTRL_DIR}"/pcmd.sh -m "nodeman" "chown blueking.blueking -R ${INSTALL_PATH}/public/bknodeman/"

}

_initdata_cmdb () {
    local tmpfile
    tmpfile=$(mktemp /tmp/init_cmdb.XXXXXXXXX)
    trap 'rm -f $tmpfile' EXIT

    emphasize "migrate mongodb"
    curl -s -X POST \
    -H 'Content-Type:application/json' \
    -H 'BK_USER:migrate' \
    -H 'HTTP_BLUEKING_SUPPLIER_ID:0' \
    "http://cmdb-admin.service.consul:$BK_CMDB_ADMIN_PORT/migrate/v3/migrate/enterprise/0" > "${tmpfile}" 2>&1

    jq . "${tmpfile}"
    if ! [[ $(jq .result "${tmpfile}") =~ 'true' ]]; then
        err "cmdb migrate mongodb failed!"
    else
        emphasize "cmdb migrate mongodb success!"
    fi

    emphasize "Registration authority model for cmdb"
    curl -s -X POST \
    -H 'Content-Type:application/json' \
    -H 'BK_USER:migrate' \
    -H 'HTTP_BLUEKING_SUPPLIER_ID:0' \
    --data '{"host": "http://cmdb-auth.service.consul:'$BK_CMDB_AUTH_PORT'"}'  "http://cmdb-admin.service.consul:$BK_CMDB_ADMIN_PORT/migrate/v3/authcenter/init" > "${tmpfile}" 2>&1
    jq . "${tmpfile}"
    if ! [[ $(jq .result "${tmpfile}") =~ 'true' ]]; then
        err "cmdb registration authority model failed"
    else
        emphasize "cmdb registration authority model success"
    fi

    emphasize "Registration gse dataid"
    curl -s -X POST \
    -H 'Content-Type:application/json' \
    -H 'BK_USER:migrate' \
    -H 'HTTP_BLUEKING_SUPPLIER_ID:0' \
    "http://cmdb-admin.service.consul:$BK_CMDB_ADMIN_PORT/migrate/v3/migrate/old/dataid" > "${tmpfile}" 2>&1

    jq . "${tmpfile}"
    if ! [[ $(jq .result "${tmpfile}") =~ 'true' ]]; then
        err "cmdb registration gse dataid failed"
    else
        emphasize "cmdb registration gse dataid success"
    fi

}
 

_initdata_paas () {
    curl --connect-timeout 10 \
        -H 'Content-Type:application/x-www-form-urlencoded' \
        -X POST \
        -d "mq_ip=rabbitmq.service.consul&username=$BK_RABBITMQ_ADMIN_USER&password=$BK_RABBITMQ_ADMIN_PASSWORD" \
        "http://$BK_PAAS_PRIVATE_ADDR/v1/rabbitmq/init/" || return 1
    # 初始化saas环境变量
    add_saas_environment
}

_initdata_topo () {
    local ip mod
    mod="$1"
    if [[ -z "${mod}" || "${mod}" -ne 1 ]]; then
        # 创建服务模板
        /opt/py36/bin/python "${CTRL_DIR}"/bin/create_blueking_set.py -c "${BK_PAAS_APP_CODE}"  -t "${BK_PAAS_APP_SECRET}"  --tpl "${CTRL_DIR}"/bin/default/blueking_service_module.tpl --create-service
        # 创建集群模板
        "${CTRL_DIR}"/bin/create_blueking_topo_template.sh "${CTRL_DIR}"/bin/default/blueking_topo_module.tpl
        # 创建蓝鲸集群
        /opt/py36/bin/python "${CTRL_DIR}"/bin/create_blueking_set.py -c "${BK_PAAS_APP_CODE}"  -t "${BK_PAAS_APP_SECRET}" --create-set
    fi
    # 转移主机到模块
    for ip in "${ALL_IP[@]}"; do
        tmpfile=$(mktemp /tmp/init_topo.XXXXXXXXX)
        "${CTRL_DIR}"/pcmd.sh -H "${ip}" "cat ${BK_HOME}/.installed_module" > "${tmpfile}"
        /opt/py36/bin/python "${CTRL_DIR}"/bin/create_blueking_set.py -c "${BK_PAAS_APP_CODE}"  -t "${BK_PAAS_APP_SECRET}" --create-proc-instance -f "${tmpfile}" && rm -f  "${tmpfile}" || return 1
    done
}

_initdata_es7 () {
    # 监控禁止产生以 write 开头的index
    source <(/opt/py36/bin/python ${CTRL_DIR}/qq.py -s -P ${CTRL_DIR}/bin/default/port.yaml)
    rest_port=$(awk -F ',' '{print $1}' <<<"${_project_port["es7,default"]}")
    host="${_project_consul["es7,default"]}"
    data=$(cat <<EOF
{
   "persistent": {
        "action.auto_create_index": "-write_*,*"
    }
}
EOF
)
    wait_ns_alive "${host}".service.consul  || fail "es7 启动失败"
    resp=$(curl -s -u elastic:"${BK_ES7_ADMIN_PASSWORD}" http://"${host}".service.consul:"${rest_port}"/_cluster/health |jq .status) 
    if [[ $resp != '"red"' ]]; then
        curl -X PUT -w "\n" -s -u elastic:"${BK_ES7_ADMIN_PASSWORD}" "${host}.service.consul:${rest_port}/_cluster/settings" -H 'Content-Type: application/json'  --data "${data}"  
    else
        echo "es7 集群状态异常, msg -> ${resp}"
        return 1
    fi
} 

_initdata_lesscode () {
    cost_time_attention
    "${CTRL_DIR}"/pcmd.sh -m lesscode "cd '${INSTALL_PATH}'/lesscode && npm run build"
}
