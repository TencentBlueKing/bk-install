#!/usr/bin/env bash
# 组件运行状态查看脚本 只能中控机执行
SELF_DIR=$(dirname "$(readlink -f "$0")")
source "${SELF_DIR}"/functions
source "${SELF_DIR}"/tools.sh
# set -e

module=$1
project=$2
# 支持判断一下target 
target=$3


if ! [ -z ${target} ]; then
    if ! grep "[0-9]" <<<${target} >/dev/null; then
        err "不支持多project"
    else
        module_ip=BK_${module^^}_IP${target}
        if [[ -z ${!module_ip} ]]; then
            err "${module_ip} 不存在"
        else
            target=${!module_ip}
        fi
    fi
else    
    if ! [ -z ${project} ]; then
        if grep "[0-9]" <<<${project} >/dev/null; then
            module_ip=BK_${module^^}_IP${project}
            if [[ -z ${!module_ip} ]]; then
                err "${module_ip} 不存在"
            else
                target=${!module_ip}
                project=""
            fi
        else
            target=${module}
        fi
    else
        target=${module}
    fi

fi

declare -a THIRD_PARTY_SVC=(
    consul
    consul-template
    mysql@[a-z]+
    redis@[a-z]+
    openresty
    rabbitmq-server
    zookeeper
    mongod
    kafka
    elasticsearch
    influxdb
    beanstalkd
)
TMP_PTN=$(printf "%s|" "${THIRD_PARTY_SVC[@]}")
THIRD_PARTY_SVC_PTN="^(${TMP_PTN%|})\.service$"

declare -A SERVICE=(
    ["mysql"]=mysql@default
    ['redis']=redis@default
    ["es7"]=elasticsearch
    ["nodeman"]=bk-nodeman
    ["consul"]=consul
    ["kafka"]=kafka
    ["usermgr"]=bk-usermgr
    ["redis_sentinel"]=redis-sentinel@default
    ["rabbitmq"]=rabbitmq-server
    ["zk"]=zookeeper
    ["mongodb"]=mongod
    ["influxdb"]=influxdb
    ["nginx"]=openresty
    ["beanstalk"]=beanstalkd
    ["yum"]=bk-yum
    ["fta"]=bk-fta
    ["iam"]=bk-iam
    ["ssm"]=bk-ssm
    ["license"]=bk-license
    ["appo"]=bk-paasagent
    ["appt"]=bk-paasagent
    ["nfs"]=nfs-server
    ['consul-template']=consul-template
    ['lesscode']=bk-lesscode
    ['iam_search_engine']=bk-iam-search-engine
    ['apigw']=bk-apigw
    ['auth']=bk-auth
    ['etcd']=etcd
    ['apisix']=apisix
)

declare -A BCS_SERVICE=(
    ['bcs']=bcs-[a-z].*
    ['zk']=zookeeper
    ['etcd']=etcd
    ['harbor_api']=harbor_api
    ['devops']=devops
    ['redis']=redis@bcs
    ['zk']=zookeeper
    ['mongodb']=mongod
    ['mysql']=mysql@bcs
)

case $module in 
    cmdb|gse|job)
        module=${module#bk}
        target_name=$(map_module_name "${module}")
        source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
        if [[ -z ${project} ]]; then
            projects=${_projects["${module}"]}
            pcmdrc "${target}" "get_common_bk_service_status ${module} ${projects[*]}"
        else
            if [[ ${module}  == 'paas' ]];then
                pcmdrc "${target}" "get_spic_bk_service_status ${module} ${project}"
            else 
                pcmdrc "${target}" "get_common_bk_service_status ${module} ${project}"
            fi
        fi
        ;;
    paas)
        module=${module#bk}
        target_name=$(map_module_name "${module}")
        source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
        if [[ -z ${project} ]]; then
            projects=${_projects["${module}"]}
            pcmdrc "${target}" "get_common_bk_service_status ${module}"
        else
            pcmdrc "${target}" "get_spic_bk_service_status ${module} ${project}"
        fi
        ;;
    monitorv3|bkmonitorv3|log|bklog)
        module=${module#bk*}
        target_name=$(map_module_name "$module")
        source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
        if [ -z "${project}" ];then
            for project in ${_projects[${module}]};do
                emphasize "status ${module} ${project} on host: ${_project_ip["${target_name},${project}"]}"
                if [[ "${module}" =~ "log" ]]; then
                    pcmdrc "${_project_ip["${target_name},${project}"]}" "get_service_status bk-${module}-${project}"
                else
                    pcmdrc "${_project_ip["${target_name},${project}"]}" "get_service_status bk-${project}"
                fi
            done
        else
            emphasize "status ${module} ${project} on host: ${_project_ip["${target_name},${project}"]}"
            if [[ "${module}" =~ "log" ]]; then
                pcmdrc "${_project_ip["${target_name},${project}"]}" "get_service_status bk-${module}-${project}"
            else
                pcmdrc "${_project_ip["${target_name},${project}"]}" "get_service_status bk-${project}"
            fi
        fi
        ;;
    nginx)  
        pcmdrc "${target}" "get_service_status ${SERVICE[$module]} ${SERVICE["consul-template"]}"
        ;;
    yum)
        # 中控机安装模块
        pcmdrc "$LAN_IP" "get_service_status ${SERVICE[$module]}"
        ;;
    bkiam|bkssm|bkiam_search_engine|bkauth)
        target_name=${module#bk}
        pcmdrc "${target_name}" "get_service_status ${SERVICE[${target_name}]}"
        ;;
    apigw|bkapigw)
        target_name=${module#bk}
        pcmdrc "${target_name}" "get_service_status ${SERVICE[${target_name}]}"
        ;;
    apisix)
        target_name=apigw
        pcmdrc "${target_name}" "get_service_status apisix"
        ;;
    etcd)
        target_name=${module#bk}
        pcmdrc "${target_name}" "get_service_status ${SERVICE[${target_name}]}"
        ;;
    bknodeman|nodeman)
        target_name=${module#bk}
        pcmdrc "${target_name}" "get_service_status ${SERVICE[${target_name}]} ${SERVICE["consul-template"]} ${SERVICE["nginx"]}"
        ;;
    paas_plugins|paas_plugin)
        pcmdrc "${BK_PAAS_IP0}" "get_service_status bk-paas-plugins-log-alert"
        pcmdrc paas "get_service_status bk-logstash-paas-app-log bk-logstash-apigw-log bk-filebeat@paas_esb_api bk-filebeat@bkapigateway_apigateway_api bk-filebeat@bkapigateway_esb_api"
        if ! [ -z "${BK_APPT_IP_COMMA}" ]; then
            pcmdrc appt "get_service_status bk-filebeat@celery  bk-filebeat@component bk-filebeat@django bk-filebeat@java bk-filebeat@uwsgi"
        fi
        pcmdrc appo "get_service_status bk-filebeat@celery  bk-filebeat@component bk-filebeat@django bk-filebeat@java bk-filebeat@uwsgi"
        ;;
    bkall)
        pcmdrc all "FORCE_TTY=1 $CTRL_DIR/bin/bks.sh ^bk-"
        ;;
    tpall)
        pcmdrc all "FORCE_TTY=1 $CTRL_DIR/bin/bks.sh \"$THIRD_PARTY_SVC_PTN\" "
        ;;
    all)
        echo "Status of all blueking components: "
        pcmdrc all "FORCE_TTY=1 $CTRL_DIR/bin/bks.sh ^bk-"
        echo 
        echo "Status of all third-party components: "
        pcmdrc all "FORCE_TTY=1 $CTRL_DIR/bin/bks.sh \"$THIRD_PARTY_SVC_PTN\" "
        ;;
    bcs)
        if [[ -n ${project} ]]; then
            if [[ "${project}" == "redis" || "${project}" == "zk" || "${project}" == "mongodb" || "${project}" == "mysql" || "${project}" == "harbor_api" || "${project}" == "devops" || "${project}" == "etcd" ]]; then
                bcs_module_ip="BK_${project^^}_${module^^}_IP_COMMA"
                IFS="," read -r -a target_server<<<"${!bcs_module_ip}"
                for ip in ${target_server[@]}; do
                    project=${project//_/-}
                    emphasize "status ${module} ${project} on host: ${ip}"
                    pcmdrc "${ip}" "get_service_status ${BCS_SERVICE[$project]}"
                done
            else
                bcs_module_ip="BK_${module^^}_${project^^}_IP_COMMA"
                IFS="," read -r -a target_server<<<"${!bcs_module_ip}"
                for ip in ${target_server[@]}; do
                    project=${project//_/-}
                    emphasize "status ${module} ${project} on host: ${ip}"
                    pcmdrc "${ip}" "get_service_status bcs-${project}"
                done

            fi
        else
            pcmdrc "bcs" "get_service_status ${BCS_SERVICE[$module]}"
            pcmdrc "etcd" "get_service_status ${BCS_SERVICE[etcd]}"
            pcmdrc "devops" "get_service_status ${BCS_SERVICE[devops]}"
            pcmdrc "harbor_api" "get_service_status ${BCS_SERVICE[harbor_api]}"
            IFS="," read -r -a target_ips<<<"${BK_REDIS_BCS_IP_COMMA}"
            for ip in ${target_ips[@]}; do
            pcmdrc "$ip" "get_service_status ${BCS_SERVICE[redis]}"
            done

            IFS="," read -r -a target_ips<<<"${BK_ZK_BCS_IP_COMMA}"
            for ip in ${target_ips[@]}; do
            pcmdrc "$ip" "get_service_status ${BCS_SERVICE[zk]}"
            done

            IFS="," read -r -a target_ips<<<"${BK_MONGODB_BCS_IP_COMMA}"
            for ip in ${target_ips[@]}; do
            pcmdrc "$ip" "get_service_status ${BCS_SERVICE[mongodb]}"
            done

            IFS="," read -r -a target_ips<<<"${BK_MYSQL_BCS_IP_COMMA}"
            for ip in ${target_ips[@]}; do
            pcmdrc "$ip" "get_service_status ${BCS_SERVICE[mysql]}"
            done

        fi
        ;;
    *)  
        if [[ -z ${SERVICE[$module]} ]]; then
            echo  "当前不支持 '${module}' 的状态检测."
            exit 1
        fi
        pcmdrc "${target}" "get_service_status ${SERVICE[$module]}"
        ;;
esac