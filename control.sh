#!/usr/bin/env bash
# shellcheck disable=SC1090
# Description: wrapper for using systemctl to operate process on remote hosts
# Usage: 
#       ./control.sh start paas [esb] [0]   # 启动paas模块esb工程的第一台服务
#       ./control.sh start paas [esb]       # 启动paas模块esb工程的所有服务
#       ./control.sh start paas             # 启动paas模块所有工程
#       ./control.sh <action>               # action可以换成(start,stop,reload,restart)
# Note:
#      paas_plugins,job等不支持精细化的

SELF_DIR=$(dirname "$(readlink -f "$0")")
source "${SELF_DIR}"/functions
source "${SELF_DIR}"/tools.sh

action=$1
# shift
module=$2
project=$3
# 支持判断一下target 
target=$4


special=(bkmonitorv3 monitorv3 bklog log)  # 可拆分服务器部署模块特例

common_bk=(bkssm bkiam bknodeman) # 兼容模块名称不统一
if is_string_in_array ${module} ${common_bk[@]}; then
    module=${module#bk}
fi

if ! [[ $project =~ ^[0-9]+$ ]]; then  
    project=${project/-/_}  # 处理project存在 '-' 时，ip地址拼接问题
fi

set -e
if [[ -n ${target} ]]; then 
    if ! [[ $target =~ ^[0-9]+$ ]]; then  # 如果存在第4个参数，判断是否为数字
        err "不支持多project"
    elif is_string_in_array ${module} ${special[@]}; then  # 判断执行模块是否属于特例，为了兼容整体部署与bkmonitorv3这种分模块部署的情况
        tmp=${module#bk} # 截取special中的bk开头
        module_ip=BK_${tmp^^}_${project^^}_IP${target} #  拼接 BK_MONITORV3_TRANSFER_IP0 这种字符串
        if [[ -z ${!module_ip} ]]; then
            err "${module_ip} 不存在"
        else
            target=${!module_ip}   # 获取到真实的ip地址---> ./bkcli stop bkmonitorv3 transefer 1 
        fi
    else
        module_ip=BK_${module^^}_IP${target} # 第三个参数为数字 并且不属于拆分服务器部署的蓝鲸组件
        if [[ -z ${!module_ip} ]]; then
            err "${module_ip} 不存在"  # 不存在对应ip则退出
        else
            target=${!module_ip} # 获取到真实的ip地址---> ./bkcli stop cmdb 1
        fi
    fi
else    
    if [[ -n ${project} ]]; then  # 如果不存在第4个参数，并且存在第三个参数
        if [[ $project =~ ^[0-9]+$ ]]; then   
            module_ip=BK_${module^^}_IP${project}  # 第三个参数为数字 ，拼接出 BK_MONIOTRV3_IP0 这种字符串
            if [[ -z ${!module_ip} ]]; then   # 判断是否存在对应的真实ip
                err "${module_ip} 不存在"
            else
                target=${!module_ip} # 获取到真实ip地址 并退出判断逻辑---> ./bkcli stop cmdb 1 
                project=""
            fi
        else
            target=${module}   # 第三个参数为字符串，并且不存在第四个参数，也就是---> ./bkcli stop cmdb admin
        fi
    else
        target=${module}  # 不存在第三、四个参数 ---> ./bkcli stop cmdb 
    fi
fi
set +e

case ${module} in 
    paas_plugin|paas_plugins)
        emphasize "${action} ${module} on host: paas"
        pcmdrc "paas" "action_paas_plugins $action paas" 
        emphasize "${action} ${module} on host: appo"
        pcmdrc "appo" "action_paas_plugins $action appo" 
        if [[ -n ${BK_APPT_IP_COMMA} ]];then
            emphasize "${action} ${module} on host: appt"
            pcmdrc "appt" "action_paas_plugins $action appt" 
        fi
        ;;
    monitorv3|bkmonitorv3|log|bklog)
        module=${module#bk*}
        target_name=$(map_module_name "$module")
        source <(/opt/py36/bin/python "${SELF_DIR}"/qq.py -p "${BK_PKG_SRC_PATH}"/"${target_name}"/projects.yaml -P "${SELF_DIR}"/bin/default/port.yaml -i ${target})
        if [ -z "${project}" ];then
            for project in ${_projects[${module}]}; do
                IFS="," read -r -a target_server<<<"${_project_ip["${target_name},${project}"]}"
                for ip in "${target_server[@]}"; do
                    emphasize "${action} ${module} ${project} on host: ${ip}"
                    pcmdrc "$ip" "action_${module} ${action} ${project}"
                done
            done
        else
            project=${project/_/-} # 兼容之前修改模块名称分隔符为 '_'
            IFS="," read -r -a target_server<<<"${_project_ip["${target_name},${project}"]}"
            for ip in "${target_server[@]}"; do
                emphasize "${action} ${module} ${project} on host: ${ip}"
                pcmdrc "$ip" "action_${module} ${action} ${project}"
            done
        fi
        ;;
    nginx)
        emphasize "${action} ${module} ${project} on host: ${target}"
        pcmdrc "${target}"  "action_${module} ${action} ${project}"

        emphasize "${action} consul-template on host: ${target}"
        pcmdrc "${target}" "action_consul_template ${action} ${project}"
        ;;
    bkssm|ssm|bkiam|iam|iam_search_engine|bkiam_search_engine|auth|bkauth)
        emphasize "${action} ${module} ${project} on host: ${module}"
        pcmdrc "${target#bk}"  "action_${module#bk*} ${action} ${project}"
        ;;
    apigw|bkapigw)
        emphasize "${action} ${module} ${project} on host: ${module}"
        pcmdrc "${target#bk}"  "action_${module#bk*} ${action} ${project}"
        ;;
    apisix)
        emphasize "${action} ${module} ${project} on host: ${module}"
        pcmdrc apigw  "action_${module#bk*} ${action} ${project}"
        ;;
    etcd)
        emphasize "${action} ${module} ${project} on host: ${module}"
        pcmdrc "${target#bk}"  "action_${module#bk*} ${action} ${project}"
        ;;
    bknodeman|nodeman)
        # 使用示例: 
        #    ./bkcli restart bknodeman   重启nodeman全部后台进程
        #    ./bkcli restart bknodeman nodeman  只重启bknodeman后台的nodeman进程
        declare -A NODEMAN_SERVICE=(
            [nodeman]="nodeman"
            [consul_template]='consul_template'
            [nginx]="nginx"
        )
        emphasize "${action} ${module} ${project} on host: ${module}"
        module=${module#bk*}
        SERVICES=( ${!NODEMAN_SERVICE[@]} )
        if [[ ${project} =~ ^[a-z] ]]; then
            if [[ ! ${SERVICES[*]} =~ ${project} ]]; then
                err "${module} not exist backend module like: ${project}"
            else
                project="${project/-/_}" # 兼容consul-template 和 consul_template
                pcmdrc "${target#bk}"  "action_${NODEMAN_SERVICE[${project}]} ${action} ${project}"
            fi
        else
            for service in ${SERVICES[*]}; do
                pcmdrc "${target#bk}"  "action_${service} ${action}"
            done
        fi
    ;;
    cmdb)
        emphasize "${action} ${module} ${project} on host: ${target}"
        pcmdrc "${target}"  "action_${module} ${action} ${project}"
        ;;
    job)
        if [[ ${action} = "start" || ${action} = "restart" ]]; then
            if [ -z "${project}" ]; then
                set -e
                emphasize "$action ${module}-config on host: ${BK_JOB_IP_COMMA}"
                "${SELF_DIR}"/pcmd.sh -H "${BK_JOB_IP_COMMA}" "systemctl $action bk-job-config"
                emphasize "$action bk-${module}.target on host: ${BK_JOB_IP_COMMA}"
                cost_time_attention
                "${SELF_DIR}"/pcmd.sh -H "${BK_JOB_IP_COMMA}" "systemctl $action bk-job.target"
                emphasize "${module} health check"
                wait_return_code "${module}" 120 || err "job 健康检查失败 请重新启动"
                set +e
            else
                emphasize "${action} ${module} ${project} on host: ${target}"
                pcmdrc "${target}"  "action_${module} ${action} ${project}"
            fi
        else
            emphasize "${action} ${module} ${project} on host: ${target}"
            pcmdrc "${target}"  "action_${module} ${action} ${project}"
        fi
        ;;
    yum)
        emphasize "${action} ${module} ${project} on host: Controller Host"
        pcmdrc "$LAN_IP"  "action_${module} ${action} ${project}"
        ;;
    saas-o)
        if [[ ${action} = "restart" ]]; then
            err "${module} 不支持该启动方式: ${action}"
            exit 1
        fi
        emphasize "${action} ${module} ${project}"
        pcmdrc appo "action_saas ${action} ${project}"
        ;;
    saas-t)
        if [[ ${action} = "restart" ]]; then
            err "${module} 不支持该启动方式: ${action}"
            exit 1
        fi
        emphasize "${action} ${module} ${project}"
        pcmdrc appt "action_saas ${action} ${project}"
        ;;
    bcs)
        if [[ ${action} = "stop" && -z ${project} || ${action} = "start" && -z ${project} ]]; then

            BCS_SVC=(api dns_service storage ops cc web_console thanos_query thanos_relay thanos_sd_svc thanos_sd_target monitor_ruler grafana monitor_alertmanager monitor_api)
            BCS_THIRD_SVC=(redis mysql mongodb harbor_api zk devops etcd)

            for project in ${BCS_THIRD_SVC[@]}
            do

                if [[ "$project" == "etcd" ]]; then
                    emphasize "${action} ${module} ${project} on host: ${ip}"
                    pcmdrc "$project" "action_${module} ${action} ${project}"
                else
                    bcs_third_project_ips=BK_${project^^}_${module^^}_IP_COMMA
                    IFS="," read -r -a target_server<<<"${!bcs_third_project_ips}"
                    for ip in ${target_server[@]}; do
                    project=${project//_/-}
                    emphasize "${action} ${module} ${project} on host: ${ip}"
                    pcmdrc "${ip}" "action_${module} ${action} ${project}"
                done
                fi
            done

            for project in ${BCS_SVC[@]}
            do
                bcs_project_ips=BK_${module^^}_${project^^}_IP_COMMA
                IFS="," read -r -a target_server<<<"${!bcs_project_ips}"
                for ip in ${target_server[@]}; do
                    project=${project//_/-}
                    emphasize "${action} ${module} ${project} on host: ${ip}"
                    pcmdrc "${ip}" "action_${module} ${action} ${project}"
                done
            done

        else
            if [[ "${project}" = "redis" || "${project}" = "zk" || "${project}" = "mongodb" || "${project}" = "harbor_api" || "${project}" = "devops" || "${project}" = "etcd" ]]; then
                bcs_module_ip="BK_${project^^}_${module^^}_IP_COMMA"
                IFS="," read -r -a target_server<<<"${!bcs_module_ip}"
                for ip in ${target_server[@]}; do
                    project=${project//_/-}
                    emphasize "${action} ${module} ${project} on host: ${ip}"
                    pcmdrc "${ip}" "action_${module} ${action} ${project}"
                done
            else
                bcs_ip="BK_${module^^}_${project^^}_IP_COMMA"
                IFS="," read -r -a target_server<<<"${!bcs_ip}"
                for ip in ${target_server[@]}; do
                project=${project//_/-}
                emphasize "${action} ${module} ${project} on host: ${ip}"
                pcmdrc "${ip}" "action_${module} ${action} ${project}"
                done
            fi

        fi
        ;;
    *)
        emphasize "${action} ${module} ${project} on host: ${target}"
        pcmdrc "${target}"  "action_${module} ${action} ${project}"
        ;;
esac