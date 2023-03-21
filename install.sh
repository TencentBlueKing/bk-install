#!/usr/bin/env bash
# vim:ft=sh sts=4 ts=4 sw=4 expandtab nu ai
# set -euo pipefail
SELF_DIR=$(dirname "$(readlink -f "$0")")
source "${SELF_DIR}"/load_env.sh
source "${SELF_DIR}"/initdata.sh
source "${SELF_DIR}"/tools.sh

set -e

install_nfs () {
    emphasize "install nfs on host: ${BK_NFS_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m nfs "${CTRL_DIR}/bin/install_nfs.sh -d ${INSTALL_PATH}/public/nfs"
    emphasize "sign host as module"
    pcmdrc "${BK_NFS_IP_COMMA}" "_sign_host_as_module nfs"
}

install_yum () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local HTTP_PORT=${_project_port["yum,default"]}
    local PYTHON_PATH="/opt/py27/bin/python"
    [[ -d "${BK_YUM_PKG_PATH}"/repodata ]]  && rm -rf "'${BK_YUM_PKG_PATH}'/repodata"
    emphasize "install bk yum on host: 中控机"
    "${SELF_DIR}"/bin/install_yum.sh -P "${HTTP_PORT}" -p /opt/yum -python "${PYTHON_PATH}"
    emphasize "add or update repo on host: ${ALL_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m ALL "'${SELF_DIR}'/bin/setup_local_yum.sh -l http://$LAN_IP:${HTTP_PORT} -a"
    "${SELF_DIR}"/pcmd.sh -m ALL "yum makecache"
    emphasize "sign host as module"
    pcmdrc "${LAN_IP}" "_sign_host_as_module yum"
    # special: 蓝鲸业务中控机模块标记
    pcmdrc "${LAN_IP}" "_sign_host_as_module controller_ip"
}

install_beanstalk () {
    local module="beanstalk"
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    emphasize  "install beanstalk on host: ${BK_BEANSTALK_IP_COMMA}"
    ${SELF_DIR}/pcmd.sh -m beanstalk "yum install  -y beanstalkd && systemctl enable --now beanstalkd && systemctl start beanstalkd"
    # 注册consul
    emphasize "register ${_project_port["$module,default"]}  consul server  on host: ${BK_BEANSTALK_IP_COMMA} "
    reg_consul_svc "${_project_consul["$module,default"]}" "${_project_port["$module,default"]}" "${BK_BEANSTALK_IP_COMMA}"
    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_consul () {
    local module=consul 
    SERVER_IP="${BK_CONSUL_IP[@]}"
    # 允许返回码非0，兼容所有的服务器都是consul server
    set +e
    BK_CONSUL_CLIENT_IP=($(printf "%s\n" ${ALL_IP[@]}  | grep -vwE ""${SERVER_IP// /|}"" ))
    set -e
    # 部署consul server
    emphasize "install consul server on host: ${BK_CONSUL_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m $module  "${CTRL_DIR}/bin/install_consul.sh  \
                -e '$BK_CONSUL_KEYSTR_32BYTES' -j '$BK_CONSUL_IP_COMMA' -r server --dns-port 53 -b \$LAN_IP -n '${#BK_CONSUL_IP[@]}'"
    # 部署consul client
    if ! [[ -z "$BK_CONSUL_CLIENT_IP" ]]; then
        emphasize "install consul client on host: ${BK_CONSUL_CLIENT_IP[@]}"
        "${SELF_DIR}"/pcmd.sh -H $(printf "%s," "${BK_CONSUL_CLIENT_IP[@]}") "${CTRL_DIR}/bin/install_consul.sh \
                    -e '$BK_CONSUL_KEYSTR_32BYTES' -j '$BK_CONSUL_IP_COMMA' -r client --dns-port 53 -b \$LAN_IP"
    fi
    emphasize "sign host as module"
    pcmdrc consul "_sign_host_as_module ${module}"
}

install_pypi () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=pypi
    local http_port=${_project_port["$module,default"]}
    local pkg_path="${BK_PYPI_PKG_PATH}"
    local python_path=/opt/py27
    if [ ! -d $pkg_path ];then err "$pkg_path不存在";fi

    # 中控机部署pypiserver
    "${SELF_DIR}"/bin/setup_local_pypiserver.sh -P $python_path -d "${pkg_path}" -a -p "${http_port}" -s "${BK_PKG_SRC_PATH}" -l "${LAN_IP}"  || return 1

    # 所有蓝鲸服务器配置PYPI源
    "${SELF_DIR}"/pcmd.sh -H "$ALL_IP_COMMA" "${CTRL_DIR}"/bin/setup_local_pypiserver.sh -c

    # 注册consul
    reg_consul_svc "${_project_consul["$module,default"]}" "${http_port}" "$LAN_IP"
}

install_controller () {
    emphasize "install controller source"
    local extar="$1"
    if [ -z "${extar}" ]; then
        "${CTRL_DIR}"/bin/install_controller.sh
    else
        "${CTRL_DIR}"/bin/install_controller.sh -e
    fi
}

install_bkenv () {
    # 不完善 存在模块排序与互相依赖问题
    local module m
    # local host_tag_file=dbadmin.env
    local projects=(dbadmin.env 
                    global.env 
                    paas.env  
                    license.env 
                    bkiam.env  
                    bkssm.env 
                    bkauth.env
                    usermgr.env 
                    paasagent.env 
                    cmdb.env 
                    gse.env 
                    job.env 
                    paas_plugins.env 
                    bknodeman.env 
                    bkmonitorv3.env  
                    bklog.env 
                    lesscode.env
                    fta.env
                    bkiam_search_engine.env
                    bkapigw.env)

    # 生成bkrc
    set +e
    gen_bkrc
    
    cd "${SELF_DIR}"/bin/default
    for m in "${projects[@]}"; do
        module=${m%.env}
        # generate文件只生成一次
        if [[ ! -f ${HOME}/.tag/$m ]]; then
            case $module in
                global|license|paasagent) : ;;
                *) "${SELF_DIR}"/bin/generate_blueking_generate_envvars.sh "$module" > "${SELF_DIR}/bin/01-generate/$module.env" && make_tag "$m" ;;
            esac
        fi
        if [[ $module != dbadmin ]]; then
            "${SELF_DIR}"/bin/merge_env.sh "$module"
        fi
    done

    set -e
}

install_kafka () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=kafka
    local kafka_port=${_project_port["kafka,default"]}
    local zk_port=${_project_port["zk,default"]}
    local consul=${_project_consul["kafka,default"]}
    # 同步java8安装包
    emphasize "sync java8.tgz  to kafka host: ${BK_KAFKA_IP_COMMA}"
    "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/java8.tgz" "${BK_PKG_SRC_PATH}/"

    # KAFKA服务器安装JAVA依赖
    emphasize "install java on host: ${BK_KAFKA_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_java.sh -p '${INSTALL_PATH}' -f '${BK_PKG_SRC_PATH}'/java8.tgz"

    # 部署 kafka
    emphasize "install kafka on host: ${BK_KAFKA_IP_COMMA}"
    ZK_HOSTS_TMP=$(printf "%s:${zk_port}," "${BK_ZK_IP[@]}")
    ZK_HOSTS=${ZK_HOSTS_TMP%,}  # 去除字符串尾部逗号
    "${SELF_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}/bin/install_kafka.sh -j $BK_KAFKA_IP_COMMA -z '${ZK_HOSTS}'/common_kafka -b \$LAN_IP -d ${INSTALL_PATH}/public/kafka -p '${kafka_port}'"

    # 注册 kafka consul
    emphasize "register  ${consul} consul server  on host: ${BK_KAFKA_IP_COMMA} "
    reg_consul_svc "${consul}" "${kafka_port}" "${BK_KAFKA_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_mysql_common () {
    _install_mysql "$@"
    _initdata_mysql
}

_install_mysql () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py  -s -P ${SELF_DIR}/bin/default/port.yaml)
    local project
    if  [[ -z ${project} ]]; then
        # 不传参 默认安装所有mysql模块 包括mysql , 
        # 安装mysql(paas),mysql(iam)
        for line in $(awk '/BK_MYSQL_.*_IP_COMMA/{print $0}' "${SELF_DIR}"/bin/02-dynamic/hosts.env); do
            tmp=$(awk -F '=' '{print $1}' <<<"$line")
            target_ip=$(awk -F '=' '{print $2}' <<<"$line" | sed "s/'//g")
            module=$(echo "${tmp}" | sed -r 's/.*BK_MYSQL_(.*)_IP_COMMA.*/\1/' |tr 'A-Z' 'a-z')
            mysql_user_passwd=BK_${module^^}_MYSQL_PASSWORD
            port=${_project_port["mysql,${module}"]}
            "${CTRL_DIR}"/pcmd.sh -H "${target_ip}" "${CTRL_DIR}/bin/install_mysql.sh -n ${module} -P $port -p '${BK_MYSQL_ADMIN_PASSWORD}' -d ${INSTALL_PATH}/public/mysql -l ${INSTALL_PATH}/logs/mysql -b \$LAN_IP -i"
            # mysql机器配置login-path
            "${CTRL_DIR}"/pcmd.sh -m "${module}" "'${CTRL_DIR}'/bin/setup_mysql_loginpath.sh -n '${module}-root' -h /var/run/mysql/'${module}'.mysql.socket -u root -p '$BK_MYSQL_ADMIN_PASSWORD'"
            # 中控机配置login-path
            "${SELF_DIR}"/bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,${module}"]}" -h "$LAN_IP" -u root -p "$BK_MYSQL_ADMIN_PASSWORD"
            reg_consul_svc "${_project_consul["mysql,${module}"]}" "${_project_port["mysql,${module}"]}" "${target_ip}"
        done
        # 安装 mysql
        for mysql_ip in "${BK_MYSQL_IP[@]}"; do
            if ! grep "${mysql_ip}" "${SELF_DIR}"/bin/02-dynamic/hosts.env | grep "BK_MYSQL_.*_IP_COMMA" >/dev/null; then
                emphasize "install mysql on host: ${mysql_ip}"
                "${CTRL_DIR}"/pcmd.sh -H "${mysql_ip}" "'${CTRL_DIR}'/bin/install_mysql.sh -n 'default' -P ${_project_port["mysql,default"]} -p '$BK_MYSQL_ADMIN_PASSWORD' -d '${INSTALL_PATH}'/public/mysql -l '${INSTALL_PATH}'/logs/mysql -b \$LAN_IP -i"
                # # mysql机器配置login-path
                emphasize "set mysql login path 'default-root' on host: ${mysql_ip}"
                "${CTRL_DIR}"/pcmd.sh -H "${mysql_ip}" "'${CTRL_DIR}'/bin/setup_mysql_loginpath.sh -n 'default-root' -h /var/run/mysql/'default'.mysql.socket -u root -p '$BK_MYSQL_ADMIN_PASSWORD'"
                for project in ${_projects["mysql"]}; do
                   target_ip=BK_MYSQL_${project^^}_IP_COMMA
                   if [[ -z ${!target_ip} ]]; then 
                       # 中控机配置login-path
                       emphasize "set mysql login path ${_project_consul["mysql,${project}"]} on host: 中控机"
                       "${SELF_DIR}"/bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,${project}"]}" -h "${mysql_ip}" -u root -p "$BK_MYSQL_ADMIN_PASSWORD"
                       emphasize "register ${_project_consul["mysql,${project}"]} on host ${mysql_ip}"
                       reg_consul_svc "${_project_consul["mysql,${project}"]}" "${_project_port["mysql,${project}"]}" "${mysql_ip}"
                   fi
                done
                # 中控机配置 default login-path
                emphasize "set mysql ${_project_consul["mysql,default"]} login path on host: ${mysql_ip}"
                "${SELF_DIR}"/bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,default"]}" -h "${mysql_ip}" -u root -p "$BK_MYSQL_ADMIN_PASSWORD"
                emphasize "register ${_project_consul["mysql,default"]} on host ${mysql_ip}"
                reg_consul_svc "${_project_consul["mysql,default"]}" "${_project_port["mysql,default"]}" "${mysql_ip}"
                emphasize "sign host as module"
                pcmdrc mysql "_sign_host_as_module mysql"
            fi
        done
    else
        # 传参module时， 安装对应的 mysql(paas)
        target_ip=BK_MYSQL_${project^^}_IP_COMMA
        mysql_user_passwd=BK_${project^^}_MYSQL_PASSWORD
        if [[ -z ${!target_ip} ]]; then
            fail "mysql(${project})不存在"
        fi
        consul_name=${_project_consul["mysql,${project}"]} 
        port=${_project_port["mysql,${project}"]}
        "${CTRL_DIR}"/pcmd.sh -H "${!target_ip}" "'${CTRL_DIR}'/bin/install_mysql.sh -n '${project}' -P '${_project_port["mysql,${project}"]}' -p '$BK_MYSQL_ADMIN_PASSWORD' -d '${INSTALL_PATH}'/public/mysql -l '${INSTALL_PATH}'/logs/mysql -b \$LAN_IP -i"
        # mysql机器配置login-path
        "${CTRL_DIR}"/pcmd.sh -H "${!target_ip}" "'${CTRL_DIR}'/bin/setup_mysql_loginpath.sh -n '${project}-root' -h /var/run/mysql/'${project}'.mysql.socket -u root -p  '$BK_MYSQL_ADMIN_PASSWORD'"
        # 中控机配置login-path
        "${SELF_DIR}"/bin/setup_mysql_loginpath.sh -n "${_project_consul["mysql,${project}"]}" -h "$LAN_IP" -u root -p "$BK_MYSQL_ADMIN_PASSWORD"
        reg_consul_svc "$consul_name" "$port" "${!target_ip}"
    fi

    emphasize "sign host as module"
    pcmdrc mysql "_sign_host_as_module mysql"
}


install_redis_common () {
    _install_redis "$@"
}

_install_redis () {
    local project=$1
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    if [ -z  "${project}" ]; then
        # 全部安装 包括redis(paas) redis
        for redis_ip in "${BK_REDIS_IP[@]}"; do
            if ! grep "${redis_ip}" "${SELF_DIR}"/bin/02-dynamic/hosts.env | grep -v "SENTINEL" | grep "BK_REDIS_.*_IP_COMM" >/dev/null; then
                # redis 逻辑
                emphasize "install redis on host: $redis_ip"
                "${CTRL_DIR}"/pcmd.sh -H "$redis_ip" "${CTRL_DIR}/bin/install_redis.sh -n '${_project_name["redis,default"]}' -p '${_project_port["redis,default"]}' -a '${BK_REDIS_ADMIN_PASSWORD}' -b \$LAN_IP"
                for project in ${_projects["redis"]}; do
                    tmp=BK_REDIS_${project^^}_IP_COMMA
                    if [[ -z ${!tmp} ]]; then
                        # 只有不存在redis(project)的时候注册, redis地址HOST指向BK_REDI_IP0
                        emphasize "register ${_project_consul["redis,${project}"]} on host $BK_REDIS_IP0"
                        reg_consul_svc "${_project_consul["redis,${project}"]}" "${_project_port["redis,${project}"]}" "$BK_REDIS_IP0"
                    fi
                done
                # 注册redis.service.consul 但不提供HOST给模块使用
                emphasize "register ${_project_consul["redis,default"]} on host $redis_ip"
                reg_consul_svc "${_project_consul["redis,default"]}" "${_project_port["redis,default"]}" "${redis_ip}"
                emphasize "sign host as module"
                pcmdrc redis "_sign_host_as_module redis"
            fi
        done
        for line in $(awk '/BK_REDIS_.*_IP_COMMA/{print $0}' "${SELF_DIR}"/bin/02-dynamic/hosts.env | grep -v SENTINEL); do
            # redis(project)逻辑
            tmp=$(awk -F '=' '{print $1}' <<<"$line")
            target_ip=$(awk -F '=' '{print $2}' <<<"$line" | sed "s/'//g") 
            module=$(echo ${tmp} | sed -r 's/.*BK_REDIS_(.*)_IP_COMMA.*/\1/' |tr 'A-Z' 'a-z')
            redis_single_passwd=BK_${module^^}_REDIS_PASSWORD
            emphasize "install redis on host ${target_ip} with name: ${_project_name["redis,${module}"]}"
            "${CTRL_DIR}"/pcmd.sh -H "${target_ip}" "${CTRL_DIR}/bin/install_redis.sh -n '${_project_name["redis,${module}"]}' -p '${_project_port["redis,${module}"]}' -a '${!redis_single_passwd}' -b \$LAN_IP"
            emphasize "register ${_project_consul["redis,${module}"]} on host $target_ip"
            reg_consul_svc "${_project_consul["redis,${module}"]}" "${_project_port["redis,${module}"]}" "${target_ip}"
        done
    else
        # 只安装单模块-> redis(paas)
        line=$(awk "/BK_REDIS_${project^^}_IP_COMMA/{print \$0}" "${SELF_DIR}"/bin/02-dynamic/hosts.env| grep -v SENTINEL)
        tmp=$(awk -F '=' '{print $1}' <<<"$line")
        target_ip=$(awk -F '=' '{print $2}' <<<"$line" | sed "s/'//g")
        module=$(echo "${tmp}" | sed -r 's/.*BK_REDIS_(.*)_IP_COMMA.*/\1/' |tr 'A-Z' 'a-z')
        redis_single_passwd=BK_${module^^}_REDIS_PASSWORD
        "${CTRL_DIR}"/pcmd.sh -H "${target_ip}" "${CTRL_DIR}/bin/install_redis.sh -n '${module}' -p '${_project_port["redis,${module}"]}' -a '${!redis_single_passwd}' -b \$LAN_IP"
        reg_consul_svc "${_project_consul["redis,${module}"]}" "${_project_port["redis,${module}"]}" "${target_ip}"
    fi

    emphasize "sign host as module"
    pcmdrc redis "_sign_host_as_module redis"
}

install_rabbitmq () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=rabbitmq
    local port=${_project_port["rabbitmq,default"]}

    if [[ -z ${BK_RABBITMQ_IP_COMMA} ]]; then
        err "rabbitmq 集群数为0"
    else 
        emphasize "install rabbitmq on host: ${BK_RABBITMQ_IP_COMMA}"
        "${CTRL_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}/bin/install_rabbitmq.sh -u '$BK_RABBITMQ_ADMIN_USER' -p '$BK_RABBITMQ_ADMIN_PASSWORD' -d '${INSTALL_PATH}'/public/rabbitmq -l '${INSTALL_PATH}'/logs/rabbitmq"
    fi

    if [[ ${#BK_RABBITMQ_IP[@]} -gt 1 ]]; then
        emphasize "setup rabbitmq cluster on host: ${BK_RABBITMQ_IP_COMMA}"
        "${CTRL_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/setup_rabbitmq_cluster.sh -e '$BK_RABBITMQ_ERLANG_COOKIES'"
        # 重新注册用户，兼容setup rabbitmq cluster 的时候reset 
        "${CTRL_DIR}"/pcmd.sh -H "${BK_RABBITMQ_IP0}" "rabbitmqctl delete_user guest;rabbitmqctl add_user '$BK_RABBITMQ_ADMIN_USER' '$BK_RABBITMQ_ADMIN_PASSWORD';rabbitmqctl set_user_tags '$BK_RABBITMQ_ADMIN_USER' administrator"
    fi

    # 注册consul
    emphasize "register consul ${_project_consul["rabbitmq,default"]} on host: ${BK_RABBITMQ_IP_COMMA}"
    reg_consul_svc "${_project_consul["rabbitmq,default"]}" "${port}" "${BK_RABBITMQ_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_redis_sentinel_common () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local quorum number
    local module=redis_sentinel
    local redis_single_port=$(awk -F ',' '{print $1}' <<<"${_project_port["redis_sentinel,default"]}")
    local redis_sentinel_port=$(awk -F ',' '{print $2}' <<<"${_project_port["redis_sentinel,default"]}")
    local redis_sentinel_consul=${_project_consul["redis_sentinel,default"]}
    local redis_single_passwd=${BK_REDIS_ADMIN_PASSWORD}
    local redis_sentinel_passwd=${BK_REDIS_SENTINEL_PASSWORD}
    local name=${_project_name["redis_sentinel,default"]}

    # 节点数判断
    number=${#BK_REDIS_SENTINEL_IP[@]}
    if [[ "${number}" -gt 1 ]]; then
        quorum=2
    elif [[ "${number}" -eq 0 ]]; then
        err "Install.config 中配置的 Redis Sentinel 节点数为0"
    else
        quorum=1
    fi

    # 部署单实例
    emphasize "install single redis on host: ${BK_REDIS_SENTINEL_IP_COMMA}"
    "${CTRL_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_redis.sh -n '${name}' -p '${redis_single_port}' -a '${redis_single_passwd}' -b \$LAN_IP" || return 1

    # 主从配置
    if [[ "${number}" -ne 1 ]];then
        emphasize "set redis master/slave"
        for node in "${BK_REDIS_SENTINEL_IP[@]}"; do
            if ! [[ $node == "${BK_REDIS_SENTINEL_IP0}" ]]; then
                "${CTRL_DIR}"/pcmd.sh  -H "$node" "redis-cli -a '$redis_single_passwd'  -p '$redis_single_port' -h \$LAN_IP slaveof ${BK_REDIS_SENTINEL_IP[0]} $redis_single_port"
                "${CTRL_DIR}"/pcmd.sh  -H "$node" "redis-cli -a '$redis_single_passwd'  -p '$redis_single_port' -h \$LAN_IP config rewrite"
            fi
        done
    fi

    if ! [[ -z "${BK_REDIS_SENTINEL_PASSWORD}" ]]; then
        emphasize "install redis sentinel on host: ${BK_REDIS_SENTINEL_IP_COMMA} with password ${redis_sentinel_passwd}"
        "${CTRL_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}"/bin/install_redis_sentinel.sh -M ${name} -m $BK_REDIS_SENTINEL_IP0:${redis_single_port} -q "${quorum}" -a ${redis_single_passwd} -b \$LAN_IP -s ${redis_sentinel_passwd}
    else
        emphasize "install redis sentinel on host: ${BK_REDIS_SENTINEL_IP_COMMA} without password"
        "${CTRL_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}"/bin/install_redis_sentinel.sh -M ${name} -m $BK_REDIS_SENTINEL_IP0:${redis_single_port} -q "${quorum}" -b \$LAN_IP -a ${redis_single_passwd}
    fi

    # 注册consul
    emphasize "register consul ${redis_sentinel_consul} on host: ${BK_REDIS_SENTINEL_IP_COMMA}"
    reg_consul_svc "${redis_sentinel_consul}" "${redis_sentinel_port}" "${BK_REDIS_SENTINEL_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_zk () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=zk
    local port=${_project_port["zk,default"]}
    local consul=${_project_consul["zk,default"]}
    # 同步java8安装包
    emphasize "sync java8.tgz  to zk host: ${BK_ZK_IP_COMMA}"
    "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/java8.tgz" "${BK_PKG_SRC_PATH}/"

    # # ZK服务器安装JAVA
    emphasize "install java on host: ${BK_ZK_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_java.sh -p '${INSTALL_PATH}' -f '${BK_PKG_SRC_PATH}'/java8.tgz"
    
    # 部署ZK
    emphasize "install zk on host: ${BK_ZK_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_zookeeper.sh -j '${BK_ZK_IP_COMMA}' -b \$LAN_IP -n '${#BK_ZK_IP[@]}'"

    # 注册consul
    emphasize "register  ${consul} consul server  on host: ${BK_ZK_IP_COMMA} "
    reg_consul_svc "${consul}" "${port}" "${BK_ZK_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_mongodb () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=mongodb
    local port=${_project_port["mongodb,default"]}

    # 批量部署单节点
    emphasize "install mongodb on host: ${BK_MONGODB_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_mongodb.sh -b \$LAN_IP -p '${port}' -d '${INSTALL_PATH}'/public/mongodb -l ${INSTALL_PATH}/logs/mongodb"

    # 根据MONGODB模块数量判断是否安装rs模式
    # 所有模式都为rs模式
    emphasize "Configure MongoDB to RS mode"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/setup_mongodb_rs.sh -a config -e '${BK_MONGODB_KEYSTR_32BYTES}' -j '${BK_MONGODB_IP_COMMA}'"
    "${SELF_DIR}"/pcmd.sh -H "${BK_MONGODB_IP0}" "${CTRL_DIR}/bin/setup_mongodb_rs.sh -a init -j '${BK_MONGODB_IP_COMMA}' -u '$BK_MONGODB_ADMIN_USER' -p '$BK_MONGODB_ADMIN_PASSWORD' -P '${port}'"

    # 注册consul
    for project in ${_projects["mongodb"]}; do
        local consul=${_project_consul["mongodb,${project}"]}
        emphasize "register ${consul} consul server  on host: ${BK_MONGODB_IP_COMMA} "
        reg_consul_svc "${consul}" "${port}" "${BK_MONGODB_IP_COMMA}"
    done
    emphasize "register ${_project_consul["mongodb,default"]} consul server  on host: ${BK_MONGODB_IP_COMMA} "
    reg_consul_svc "${_project_consul["mongodb,default"]}" "${_project_port["mongodb,default"]}" "${BK_MONGODB_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_es7 () {
    local ip
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=es7
    local rest_port=$(awk -F ',' '{print $1}' <<< "${_project_port["es7,default"]}")
    local transport_port=$(awk -F ',' '{print $2}' <<< "${_project_port["es7,default"]}")
    local consul=${_project_consul["es7,default"]}
    if ! [[ ${#BK_ES7_IP[@]} -eq 1 || ${#BK_ES7_IP[@]} -eq 3 ]]; then
        err "es7 节点数量预期为1或3，当前数量为: ${#BK_ES7_IP[@]}"
    fi
    emphasize "install elasticsearch7 on host: ${BK_ES7_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m es7 "$CTRL_DIR/bin/install_es.sh -b \$LAN_IP -s '${BK_ES7_IP_COMMA}' -d '${INSTALL_PATH}/public/elasticsearch' -l '${INSTALL_PATH}/logs/elasticsearch' -P '${rest_port}' -p '${transport_port}'"
    emphasize "elasticsearch7 enable x-pack plugin"
    "${SELF_DIR}"/pcmd.sh -H "${BK_ES7_IP0}" "$CTRL_DIR/bin/setup_es_auth.sh -g"
    set +e
    BK_ES7_ELSE_IP=( $(printf "%s\n" ${BK_ES7_IP[@]}  | grep -vwE "${BK_ES7_IP0// /|}") )
    set -e
    if [[ -z "${BK_ES7_ELSE_IP[*]}" ]]; then
        emphasize "elasticsearch7 enable x-pack plugin"
        "${SELF_DIR}"/pcmd.sh -m es7 "$CTRL_DIR/bin/setup_es_auth.sh -g;$CTRL_DIR/bin/setup_es_auth.sh -a"
    else
        emphasize "elasticsearch7 enable x-pack plugin on host: ${BK_ES7_IP0}"
        "${SELF_DIR}"/pcmd.sh -H "${BK_ES7_IP0}" "$CTRL_DIR/bin/setup_es_auth.sh -a"
        emphasize "sync elastic-certificates to host: $LAN_IP"
        rsync -ao "${BK_ES7_IP0}":/etc/elasticsearch/elastic-certificates.p12 "${INSTALL_PATH}"/cert/elastic-certificates.p12
        for ip in "${BK_ES7_ELSE_IP[@]}"; do
            emphasize "sync elastic-certificates to host: ${ip}" 
            rsync -ao "${INSTALL_PATH}"/cert/elastic-certificates.p12 "${ip}":/etc/elasticsearch/elastic-certificates.p12
            emphasize "chown elastic-certficates on host: ${ip}" 
            "${SELF_DIR}"/pcmd.sh -H "${ip}" "chown elasticsearch:elasticsearch /etc/elasticsearch/elastic-certificates.p12"
            emphasize "elasticsearch7 enable x-pack plugin on host: ${ip}"
            "${SELF_DIR}"/pcmd.sh -H "${ip}" "$CTRL_DIR/bin/setup_es_auth.sh -a"
        done
    fi
    emphasize "elasticsearch7 change paaword"
    "${SELF_DIR}"/pcmd.sh -H "${BK_ES7_IP0}" "source ${CTRL_DIR}/functions;wait_port_alive '${rest_port}' 50;$CTRL_DIR/bin/setup_es_auth.sh -s -b \$LAN_IP -p '$BK_ES7_ADMIN_PASSWORD'"
    # 注册consul
    emphasize "register  ${consul} consul server  on host: ${BK_ES7_IP_COMMA} "
    reg_consul_svc "${consul}" "${rest_port}" "${BK_ES7_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_influxdb () {
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -s -P ${SELF_DIR}/bin/default/port.yaml)
    local module=influxdb
    local port=${_project_port["influxdb,default"]}
    local consul=${_project_consul["influxdb,default"]}

    emphasize "install influxdb on host: ${BK_INFLUXDB_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "${CTRL_DIR}/bin/install_influxdb.sh -b \$LAN_IP -P '${port}'  \
                    -d '${INSTALL_PATH}/public/influxdb' -l '${INSTALL_PATH}/logs/influxdb' -w '${INSTALL_PATH}/public/influxdb/wal' -p '${BK_INFLUXDB_ADMIN_PASSWORD}' -u admin"

    # 注册consul
    emphasize "register  ${consul} consul server  on host: ${BK_INFLUXDB_IP_COMMA} "
    reg_consul_svc "${consul}" "${port}" "${BK_INFLUXDB_IP_COMMA}"
   
    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_license () {
    local module=license
    local port=8443

    emphasize "install license on host: ${BK_LICENSE_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "${CTRL_DIR}/bin/install_license.sh -b \$LAN_IP -e '${CTRL_DIR}'/bin/04-final/license.env -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}'"

    # 注册consul
    emphasize "register  license consul server  on host: ${BK_LICENSE_IP_COMMA} "
    reg_consul_svc "${module}" "${port}" "${BK_LICENSE_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_cert () {
    local module=cert
    "${SELF_DIR}"/pcmd.sh -m ALL "rsync -a ${BK_PKG_SRC_PATH}/cert/  ${INSTALL_PATH}/cert/ && chown blueking.blueking -R ${INSTALL_PATH}/cert/"
}

install_iam () { 
    local module=iam
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    emphasize "migrate $module sql"
    migrate_sql ${module}
    for project in ${_projects[@]}; do
        emphasize "install ${target_name}-${project} on host: ${BK_IAM_IP_COMMA}"
        local port=${_project_port["${target_name},${project}"]}
        local consul=${_project_consul["${target_name},${project}"]}
        "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_bkiam.sh -b \$LAN_IP -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -e '${CTRL_DIR}/bin/04-final/bkiam.env'"
        emphasize "register  ${consul} consul server  on host: ${BK_IAM_IP_COMMA}"
        reg_consul_svc "${consul}" "${port}" "${BK_IAM_IP_COMMA}"
    done

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_iam_search_engine () { 
    local module=iam_search_engine
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    for project in ${_projects[@]}; do
        emphasize "install ${target_name}-${project} on host: ${BK_IAM_SEARCH_ENGINE_IP_COMMA}"
        local port=${_project_port["${target_name},${project}"]}
        local consul=${_project_consul["${target_name},${project}"]}
        "${SELF_DIR}"/pcmd.sh -m "${module}" "${CTRL_DIR}/bin/install_bkiam_search_engine.sh -b \$LAN_IP -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -e '${CTRL_DIR}/bin/04-final/bkiam_search_engine.env'"
        emphasize "register  ${consul} consul server  on host: ${BK_IAM_SEARCH_ENGINE_IP_COMMA}"
        reg_consul_svc "${consul}" "${port}" "${BK_IAM_SEARCH_ENGINE_IP_COMMA}"
    done

    emphasize "add or update appocode ${BK_IAM_SAAS_APP_CODE}"
    add_or_update_appcode "$BK_IAM_SAAS_APP_CODE" "$BK_IAM_SAAS_APP_SECRET"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_ssm () {
    local module=ssm
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}
    emphasize "migrate $module sql"
    migrate_sql $module
    for project in ${projects[@]}; do
        emphasize "install ${target_name}-${project} on host: ${BK_SSM_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -H "${_project_ip["${target_name},${project}"]}" \
                 "${CTRL_DIR}/bin/install_bkssm.sh -e '${CTRL_DIR}/bin/04-final/bkssm.env' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -b \$LAN_IP"
        emphasize "register  ${consul} consul server  on host: ${BK_SSM_IP_COMMA}"
        reg_consul_svc "${_project_consul[${target_name},${project}]}"  "${_project_port[${target_name},${project}]}"  "${_project_ip[${target_name},${project}]}"
    done

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_auth () {
    local module=auth
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}

    emphasize "migrate $module sql"
    migrate_sql $module
    for project in ${projects[@]}; do
        emphasize "install ${target_name}-${project} on host: ${BK_AUTH_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -H "${_project_ip["${target_name},${project}"]}" \
                 "${CTRL_DIR}/bin/install_bkauth.sh -e '${CTRL_DIR}/bin/04-final/bkauth.env' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -b \$LAN_IP"
        emphasize "register  ${consul} consul server  on host: ${BK_AUTH_IP_COMMA}"
        reg_consul_svc "${_project_consul[${target_name},${project}]}"  "${_project_port[${target_name},${project}]}"  "${_project_ip[${target_name},${project}]}"
    done

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_cmdb () {
    _install_cmdb_project "$@"
}

_install_cmdb_project () {
    local module=cmdb
    local project=$1
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}

    emphasize "grant mongodb privilege for ${module}"
    grant_mongodb_pri ${module} 
    grant_mongodb_pri cmdb_events

    emphasize "add or update appocode ${BK_CMDB_APP_CODE}"
    add_or_update_appcode "$BK_CMDB_APP_CODE" "$BK_CMDB_APP_SECRET"

    if [[ -z ${project} ]]; then
        emphasize "install ${module} on host: $module"
        "${SELF_DIR}"/pcmd.sh -m "${module}" \
                "${CTRL_DIR}/bin/install_cmdb.sh -e '${CTRL_DIR}/bin/04-final/cmdb.env' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -l '${INSTALL_PATH}/logs/cmdb'"
    else
        # 后续cmdb原子脚本支持分模块部署的时候可走这个逻辑
        for project in ${project[@]}; do
            emphasize "install ${module}-${project} on host: $module"
            "${SELF_DIR}"/pcmd.sh -H "${_project_ip["${target_name},${project}"]}" \
                     "${CTRL_DIR}/bin/install_cmdb.sh -e '${CTRL_DIR}/bin/04-final/cmdb.env' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -m '${project}'"
        done
    fi
    emphasize "start bk-cmdb.target on host: ${module}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "systemctl start bk-cmdb-admin.service"
    sleep 10
    "${SELF_DIR}"/pcmd.sh -m "${module}" "systemctl start bk-cmdb.target"
    for project in ${projects[@]}; do
        # consul服务注册排除掉cmdb
        if ! [[ ${project} == "synchronize" ]]; then
            emphasize "register consul  ${project} on host:${_project_ip[${target_name},${project}]} "
            reg_consul_svc "${_project_consul[${target_name},${project}]}"  "${_project_port[${target_name},${project}]}"  "${_project_ip[${target_name},${project}]}"
        fi
    done

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}


install_paas () {
    _install_paas_project "$@"
}

_install_paas_project () {
    local module=paas
    local project=${1:-all}
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects["${module}"]}
    if [ "$project" == 'all' ];then project="${projects[@]}";fi
    # 创建paas相关数据库
    emphasize "migrate ${module} sql"
    migrate_sql $module
    # paas服务器同步并安装python
    emphasize "sync and install python on host: ${BK_PAAS_IP_COMMA}"
    install_python $module
    # install docker
    emphasize "install docker on host: ${module}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_docker.sh"

    # 要加判断传入值是否正确
    for project in ${project[@]}; do
        python_path=$(get_interpreter_path "paas" "paas")
        project_port=${_project_port["${target_name},${project}"]}
        project_consul=${_project_consul["${target_name},${project}"]}
        for ip in "${BK_PAAS_IP[@]}"; do 
            emphasize "install ${module}(${project}) on host: ${ip}"
            cost_time_attention
            "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_paas.sh -e '${CTRL_DIR}/bin/04-final/paas.env' -m '$project' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' -b \$LAN_IP --python-path '${python_path}'"
            emphasize "register consul ${project_consul} on host: ${ip}"
            reg_consul_svc "${project_consul}" "${project_port}" "$ip"
        done
    done

    # 注册白名单
    emphasize "add or update appcode: $BK_PAAS_APP_CODE"
    add_or_update_appcode "$BK_PAAS_APP_CODE" "$BK_PAAS_APP_SECRET"
    add_or_update_appcode "bk_console" "$BK_PAAS_APP_SECRET"
    add_or_update_appcode bk_monitorv3 bk_monitorv3

    # 注册权限模型
    emphasize "Registration authority model for ${module}"
    bkiam_migrate $module

    # 挂载nfs
    if [[ ! -z ${BK_NFS_IP_COMMA} ]]; then
        emphasize "mount nfs to host: $BK_NFS_IP0"
        pcmdrc ${module} "_mount_shared_nfs open_paas"
    fi

    # 版本信息
    _update_common_info

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_etcd () {
    local module=etcd

    # 生成 etcd 证书
    "${SELF_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}/bin/gen_etcd_certs.sh -p ${INSTALL_PATH}/cert/etcd -i ${BK_ETCD_IP[@]}"
    
    emphasize "register consul ${module} on host: ${BK_ETCD_IP[@]}"
    for ip in "${BK_ETCD_IP[@]}"; do
        "${SELF_DIR}"/pcmd.sh -m ${module} "export ETCD_CERT_PATH=${INSTALL_PATH}/cert/etcd;export ETCD_DATA_DIR=${INSTALL_PATH}/public/etcd;export PROTOCOL=https;${CTRL_DIR}/bin/install_etcd.sh ${BK_ETCD_IP[@]}"

        # 注册 consul
        reg_consul_svc "$module" "2379" "$ip"
    done
}

install_apisix () {
    local module=apisix
    emphasize "install apix on host: apigw"
    "${SELF_DIR}"/pcmd.sh -m apigw "${CTRL_DIR}/bin/install_apisix.sh -p ${INSTALL_PATH}" 
}

install_apigw_fe () {
    local module=apigw
    local target_name=$(map_module_name $module)

    emphasize "create directories ..."
    "${SELF_DIR}"/pcmd.sh -H "${BK_NGINX_IP_COMMA}" "install -o blueking -g blueking -m 755 -d  '${INSTALL_PATH}/bk_apigateway'"

    emphasize "install apigw frontend on host: ${BK_NGINX_IP_COMMA}"
    PRSYNC_EXTRA_OPTS="--delete" "${SELF_DIR}"/sync.sh nginx "${BK_PKG_SRC_PATH}/${target_name}/dashboard-fe/" "${INSTALL_PATH}/bk_apigateway/dashboard-fe/"
    "${SELF_DIR}"/pcmd.sh -m nginx "${CTRL_DIR}/bin/render_tpl -p ${INSTALL_PATH} -m ${target_name} -e ${CTRL_DIR}/bin/04-final/bkapigw.env ${BK_PKG_SRC_PATH}/bk_apigateway/support-files/templates/dashboard-fe#static#runtime#runtime.js ${BK_PKG_SRC_PATH}/bk_apigateway/support-files/templates/dashboard-fe#docs#static#runtime#runtime.js"

}

install_apigw () {
    local module=apigw
    local project=${1:-all}
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects["${module}"]}

    # 部署前端
    install_apigw_fe

    # 创建 apigw 相关数据库
    emphasize "migrate ${module} sql"
    migrate_sql $module

    # apigw 服务器同步并安装python
    emphasize "sync and install python on host: ${BK_APIGW_IP_COMMA}"
    install_python $module

    for project in dashboard bk-esb operator apigateway api-support; do
        emphasize "register consul $project on host: ${ip}"
        reg_consul_svc ${_project_consul["${module},${project}"]} ${_project_port["${module},${project}"]} "${BK_APIGW_IP_COMMA}"
    done

    # 安装 apigw
    for project in dashboard api-support bk-esb; do
        project_port=${_project_port["${module},${project}"]}
        project_consul=${_project_consul["${module},${project}"]}
        for ip in "${BK_APIGW_IP_COMMA[@]}"; do 
            emphasize "install ${module}(${project}) on host: ${ip}"
            cost_time_attention
            "${SELF_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}/bin/install_bkapigw.sh -b \$LAN_IP -m '$project' -s '${BK_PKG_SRC_PATH}' -p '${INSTALL_PATH}' --cert-path '${INSTALL_PATH}/cert/etcd' -e '${CTRL_DIR}/bin/04-final/bkapigw.env'"
        done
    done

    emphasize "add or update app_code ${BK_APIGW_APP_CODE}"
    add_or_update_appcode "$BK_APIGW_APP_CODE" "$BK_APIGW_APP_SECRET"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_python () {
    local module=$1
    local py_pkgs=(py27.tgz py36.tgz py27_e.tgz py36_e.tgz)
    local target_dir=/opt
    local target_ip="BK_${module^^}_IP[@]"
    # 同步python安装包到目标目录或目标服务器
    if ! [[ -z $module ]]; then
        for ip in ${!target_ip}; do 
            # 安装其他服务器python包
            if  "${SELF_DIR}"/pcmd.sh -H "${ip}" "grep -w 'python' ${INSTALL_PATH}/.installed_module  || echo "PYTHON_UNINSTALL"" | grep "PYTHON_UNINSTALL" >/dev/null 2>&1; then
                "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/python" "${BK_PKG_SRC_PATH}/" || err "同步PYTHON包失败"
                for pkg in "${py_pkgs[@]}"; do
                    "${SELF_DIR}"/pcmd.sh -H "${ip}"  "tar xf ${BK_PKG_SRC_PATH}/python/$pkg -C $target_dir/"
                done
                "${SELF_DIR}"/pcmd.sh -H "${ip}"  "[ -f ${INSTALL_PATH}/.installed_module ] || touch ${INSTALL_PATH}/.installed_module;echo 'python' >>${INSTALL_PATH}/.installed_module"
            else
                emphasize "skip install python on host: ${ip}"
            fi
        done
    else
        # 安装中控机python包
        for pkg in "${py_pkgs[@]}"; do
            emphasize "install python on host: $LAN_IP"
            "${SELF_DIR}"/pcmd.sh -H "$LAN_IP"  "tar xf ${BK_PKG_SRC_PATH}/python/$pkg -C $target_dir/"
        done
    fi
}

install_node () {
    local module="${1:-lesscode}"
    local pkg=$(_find_node_latest)
    local target_dir="/opt/${pkg%.tar.gz}"
    if [[ -z "${BK_PKG_SRC_PATH}"/"${pkg}" ]]; then
        err "Node js package not find"
    fi
    emphasize "sync node package to module: $module"
    "${SELF_DIR}"/sync.sh "${module}" "${BK_PKG_SRC_PATH}/$pkg" "${BK_PKG_SRC_PATH}/" || err "同步Node包失败"
    emphasize "unpack node package to directory: $target_dir"
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "tar xf ${BK_PKG_SRC_PATH}/$pkg -C /opt" 
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "chown -R blueking.blueking ${target_dir}"
    pcmdrc "${module}" "[[ -f '${target_dir}'/bin/node ]] || err '${target_dir}'/bin/node not exist"
    emphasize "Link ${target_dir}/bin/node to /usr/bin/node"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "ln -sf  '${target_dir}'/bin/node /usr/bin/node"
    emphasize "Link ${target_dir}/bin/npm to /usr/bin/npm"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "ln -sf  '${target_dir}'/bin/npm /usr/bin/npm"
}

install_consul_template () {
    local module=consul_template
    local install_module=$1
    local install_ip=$2
    emphasize "install consul template on host: ${install_ip}"
    "${SELF_DIR}"/pcmd.sh -H "${install_ip}"  "${CTRL_DIR}/bin/install_consul_template.sh -m ${install_module}"
    emphasize "start and reload consul-template on host: ${install_ip}"
    # 启动后需要reload，防止这台ip已经启动过consul-template，如果不reload，没法生效新安装的子配置
    "${SELF_DIR}"/pcmd.sh -H "${install_ip}" "systemctl start consul-template; sleep 1; systemctl reload consul-template"
}

install_nginx () {
    local module=nginx

    # 安装openresty
    emphasize "install openresty  on host: ${BK_NGINX_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}"  "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"

    # nginx 服务器上安装consul-template
    emphasize "install consul-template  on host: ${BK_NGINX_IP_COMMA}"
    install_consul_template ${module} "${BK_NGINX_IP_COMMA}"

    # 注册paas.service.consul cmdb.service.consul job.service.consul
    if [[ $BK_HTTP_SCHEMA == 'http' ]]; then 
        port=80
    else
        port=443
    fi
    for name in paas cmdb job; do
        emphasize "register consul service -> {${name}} on host ${BK_NGINX_IP_COMMA} "
        reg_consul_svc $name $port "${BK_NGINX_IP_COMMA}"
    done

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc ${module} "_sign_host_as_module consul-template"
}

install_appo () {
    local module=appo
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    if ! [ -z "${BK_APPT_IP_COMMA}" ]; then
        if is_string_in_array "${BK_APPT_IP_COMMA}" "${BK_APPO_IP[@]}"; then
            err "appo appt 不可部署在同一台服务器"
        fi
    fi
    emphasize "install docker on host: ${module}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_docker_for_paasagent.sh"

    emphasize "install ${module} on host: ${module}"
    cost_time_attention
    "${SELF_DIR}"/pcmd.sh -m ${module} \
            "${CTRL_DIR}/bin/install_paasagent.sh -e ${CTRL_DIR}/bin/04-final/paasagent.env -b \$LAN_IP -m prod -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"

    # 安装openresty
    emphasize "install openresty on host: ${BK_APPO_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"
    
    emphasize "install consul-template on host: ${BK_APPO_IP_COMMA}"
    install_consul_template "paasagent" "${BK_APPO_IP_COMMA}"

    # nfs
    if [[ ! -z ${BK_NFS_IP_COMMA} ]]; then
        emphasize "mount nfs to host: $BK_NFS_IP0"
        pcmdrc ${module} "_mount_shared_nfs ${module}"
    fi

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc ${module} "_sign_host_as_module consul-template"
}

install_appt () {
    local module=appt
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    if is_string_in_array "${BK_APPT_IP_COMMA}" "${BK_APPO_IP[@]}"; then
        err "appo appt 不可部署在同一台服务器"
    fi
    emphasize "install docker on host: ${module}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_docker_for_paasagent.sh"

    emphasize "install ${module} on host: ${module}"
    cost_time_attention
    "${SELF_DIR}"/pcmd.sh -m ${module} \
            "${CTRL_DIR}/bin/install_paasagent.sh -e ${CTRL_DIR}/bin/04-final/paasagent.env -b \$LAN_IP -m test -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"

    # 安装openresty
    emphasize "install openresty on host: ${BK_APPT_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"

    emphasize "install consul template on host: ${BK_APPT_IP_COMMA}"
    install_consul_template "paasagent" "${BK_APPT_IP_COMMA}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc ${module} "_sign_host_as_module consul-template"
}

install_job () {
    local module=$1
    case  "$module" in
        backend)
        _install_job_backend "$@"
        ;;
        frontend)
        _install_job_frontend
        ;;
        *)
        _install_job_backend 
        _install_job_frontend
        ;;
    esac
}

_install_job_frontend () {
    emphasize "create directories ..."
    "${SELF_DIR}"/pcmd.sh -H "${BK_NGINX_IP_COMMA}" "install -o blueking -g blueking -m 755 -d  '${INSTALL_PATH}/job'"
    emphasize "install job frontend on host: ${BK_NGINX_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -H "${BK_NGINX_IP_COMMA}" "${CTRL_DIR}/bin/release_job_frontend.sh -p ${INSTALL_PATH} -B ${BK_PKG_SRC_PATH}/backup -s ${BK_PKG_SRC_PATH}/ -i $BK_JOB_API_PUBLIC_URL"
}

_install_job_backend () {
    local module=job
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}
    for m in job_backup job_manage job_crontab job_execute job_analysis;do 
        # 替换_ 兼容projects.yaml 格式
        # mongod  joblog用户相关授权已经在install mongodb的时候做过
        emphasize "grant rabbitmq private for ${module}"
        grant_rabbitmq_pri ${m} "${BK_JOB_IP_COMMA}"
    done
    # esb app_code
    emphasize "add or update appcode: ${BK_JOB_APP_CODE}"
    add_or_update_appcode "$BK_JOB_APP_CODE" "$BK_JOB_APP_SECRET"
    # 导入sql
    emphasize "migrate sql for module: ${module}"
    migrate_sql ${module}

    # job依赖java环境
    ${SELF_DIR}/pcmd.sh -H ${BK_JOB_IP_COMMA} "if ! which java >/dev/null;then ${CTRL_DIR}/bin/install_java.sh -p ${INSTALL_PATH} -f ${BK_PKG_SRC_PATH}/java8.tgz;fi"

    # mongod用户授权
    emphasize "grant mongodb privilege for ${module}"
    mongo_args=$(awk -F'[:@/?]' '{printf "-u '%s' -p '%s' -d '%s'", $1, $2, $5}' <<<"${BK_JOB_LOGSVR_MONGODB_URI##mongodb://}")
    BK_MONGODB_ADMIN_PASSWORD=$(urlencode "${BK_MONGODB_ADMIN_PASSWORD}") # 兼容密码存在特殊字符时的URL编码

    "${SELF_DIR}"/pcmd.sh -H "${BK_MONGODB_IP0}" "${CTRL_DIR}/bin/add_mongodb_user.sh -i mongodb://$BK_MONGODB_ADMIN_USER:$BK_MONGODB_ADMIN_PASSWORD@\$LAN_IP:27017/admin $mongo_args"
    # 单台部署全部
    emphasize "install ${module} on host: ${BK_JOB_IP_COMMA}}"
    cost_time_attention
    ${SELF_DIR}/pcmd.sh -H ${BK_JOB_IP_COMMA} "${CTRL_DIR}/bin/install_job.sh -e ${CTRL_DIR}/bin/04-final/job.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
    emphasize "start bk-${module}.target on host: ${BK_JOB_IP_COMMA}"
    cost_time_attention "bk-job.target takes a while to fully boot up, please wait!"
    ${SELF_DIR}/pcmd.sh -H ${BK_JOB_IP_COMMA} "systemctl start bk-job.target"

    # 检查
    emphasize "${module} health check"
    wait_return_code "${module}" 120 || err "job 健康检查失败 请重新启动"

    # 权限模型
    emphasize "Registration authority model for ${module}"
    bkiam_migrate ${module}

    # nfs
    if [[ ! -z ${BK_NFS_IP_COMMA} ]]; then
        emphasize "mount nfs to host: ${BK_NFS_IP0}"
        pcmdrc job "_mount_shared_nfs job"
    fi

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_usermgr () {
    local module=usermgr
    local target_name=$(map_module_name $module)
    emphasize "migrate ${module} sql"
    migrate_sql $module
    emphasize "grant rabbitmq private for ${module}"
    grant_rabbitmq_pri $module
    emphasize "sync and install python on host: ${BK_USERMGR_IP_COMMA}"
    install_python $module

    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects[$module]}
    for project in ${projects[@]}; do
        local python_path=$(get_interpreter_path ${module} "${project}")
        for ip in "${BK_USERMGR_IP[@]}"; do
            emphasize "install ${module} ${project} on host: ${BK_USERMGR_IP_COMMA} "
            "${SELF_DIR}"/pcmd.sh -H "${ip}" \
                     "${CTRL_DIR}/bin/install_usermgr.sh -e ${CTRL_DIR}/bin/04-final/usermgr.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH} --python-path ${python_path}"
            reg_consul_svc "${_project_consul[${target_name},${project}]}" "${_project_port[${target_name},${project}]}" "${ip}"
        done
    done

    emphasize "add or update appcode: ${BK_USERMGR_APP_CODE}"
    # 注册app_code
    add_or_update_appcode "$BK_USERMGR_APP_CODE" "$BK_USERMGR_APP_SECRET"
    emphasize "Registration authority model for ${module}"
    # 注册权限模型
    bkiam_migrate ${module}

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_saas-o () {
    install_saas appo "$@"
}

install_saas-t () {
    install_saas appt "$@"
}

install_saas () {
    local env=${1:-appo}; shift 1

    source "${SELF_DIR}"/.rcmdrc

    if [ $# -ne 0 ]; then
        for app_v in "$@"; do
            app_code=${app_v%%=*}
            app_version=${app_v##*=}

            if [ "$app_version" == "$app_v" ]; then
                pkg_name=$(_find_latest_one $app_code)
            else
                # pkg_name=${app_code}_V${app_version}.tar.gz
                pkg_name=$( _find_saas $app_code $app_version )
            fi

            _install_saas $env $app_code $pkg_name
            assert " SaaS application $app_code has been deployed successfully" "Deploy saas $app_code failed."
            set_console_desktop ${app_code}
        done
    else
        all_app=( $(_find_all_saas) )
        if [ ${#all_app[@]} -eq 0 ]; then
            fail "no saas package found"
        fi

        for app_code in $(_find_all_saas); do
            _install_saas "$env" "$app_code" $(_find_latest_one "$app_code")
            assert " SaaS application $app_code has been deployed successfully" "Deploy saas $app_code failed."
            set_console_desktop ${app_code}
        done
    fi
}

_install_saas () {
    local app_env=$1
    local app_code=$2
    local pkg_name=$3

    if [ -f "$BK_PKG_SRC_PATH"/official_saas/"$pkg_name" ]; then
        step " Deploy official saas $app_code"
        /opt/py36/bin/python "${SELF_DIR}"/bin/saas.py -e "$app_env" -n "$app_code" -k "$BK_PKG_SRC_PATH"/official_saas/"$pkg_name" -f "$CTRL_DIR"/bin/04-final/paas.env
    else
        err "no package found for saas app: $app_code"
    fi
}

install_bkmonitorv3 () {
    _install_bkmonitor "$@"
}

_install_bkmonitor () {
    local module=monitorv3
    local project=$1
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    projects=${_projects[${module}]}
    if ! [[ -z "${project}" ]]; then 
        projects=$project
    fi
    emphasize "migrate $module sql"
    migrate_sql $module
    emphasize "grant rabbitmq private for ${module}"
    grant_rabbitmq_pri $module
    emphasize "install python on host: ${module}"
    install_python $module

    # 注册app_code
    emphasize "add or update appcode ${BK_MONITOR_APP_CODE}"
    add_or_update_appcode "$BK_MONITOR_APP_CODE" "$BK_MONITOR_APP_SECRET"
    add_or_update_appcode bk_monitorv3 bk_monitorv3

    for project in ${projects[@]}; do
        IFS="," read -r -a target_server<<<"${_project_ip["${target_name},${project}"]}"
        for ip in ${target_server[@]}; do
            python_path=$(get_interpreter_path $module "$project")
            emphasize "install ${module} ${project} on host: ${ip}"
            cost_time_attention
            if [[ ${python_path} =~ "python" ]]; then
                "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_bkmonitorv3.sh -b \$LAN_IP -m ${project} --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/bkmonitorv3.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
            else
                "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_bkmonitorv3.sh -b \$LAN_IP -m ${project}  -e ${CTRL_DIR}/bin/04-final/bkmonitorv3.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
            fi
            emphasize "sign host as module"
            pcmdrc "${ip}" "_sign_host_as_module ${module}_${project}"
        done
        if grep -w -E -q "grafana|unify-query" <<< "${project}"; then
           emphasize "register ${_project_consul[${target_name},${project}]} consul on host: ${_project_ip[${target_name},${project}]}"
           reg_consul_svc ${_project_consul[${target_name},${project}]}  ${_project_port[${target_name},${project}]} ${_project_ip[${target_name},${project}]}
        fi

    done

}

install_paas_plugins () {
    local module=paas_plugins
    local python_path=/opt/py27/bin/python

    emphasize "sync java11 on host: ${BK_PAAS_IP_COMMA}"
    "${SELF_DIR}"/sync.sh "paas" "${BK_PKG_SRC_PATH}/java11.tgz" "${BK_PKG_SRC_PATH}/"

    emphasize "install java11 on host: ${BK_PAAS_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "paas" "mkdir ${INSTALL_PATH}/jvm/;tar -xf ${BK_PKG_SRC_PATH}/java11.tgz --strip-component=1 -C ${INSTALL_PATH}/jvm/"

    emphasize "install log_agent,log_parser on host: ${BK_PAAS_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "paas" "${CTRL_DIR}/bin/install_paas_plugins.sh -m paas --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/paas_plugins.env \
               -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
    if ! [[ -z ${BK_APPT_IP_COMMA} ]]; then
        emphasize "install log_agent on host: ${BK_APPT_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -m "appt" "${CTRL_DIR}/bin/install_paas_plugins.sh -m appt -a appt --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/paas_plugins.env \
               -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
    fi
    if ! [[ -z ${BK_APPO_IP_COMMA} ]]; then
        emphasize "install log_agent on host: ${BK_APPO_IP_COMMA}"
        "${SELF_DIR}"/pcmd.sh -m "appo" "${CTRL_DIR}/bin/install_paas_plugins.sh -m appo -a appo --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/paas_plugins.env  -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
    fi
}

install_nodeman () {
    local module=nodeman
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    local projects=${_projects["${module}"]}
    emphasize "grant rabbitmq private for ${module}"
    grant_rabbitmq_pri $module
    emphasize "install python on host: ${module}"
    install_python $module
    # 注册app_code
    emphasize "add or update appcode ${BK_NODEMAN_APP_CODE}"
    add_or_update_appcode "$BK_NODEMAN_APP_CODE" "$BK_NODEMAN_APP_SECRET"
    for project in ${projects[@]}; do
        local python_path=$(get_interpreter_path ${module} "${project}")
        for ip in "${BK_NODEMAN_IP[@]}"; do
            emphasize "install ${module} on host: ${ip}"
            cost_time_attention
            "${SELF_DIR}"/pcmd.sh -H "${ip}" \
                     "${CTRL_DIR}/bin/install_bknodeman.sh -e ${CTRL_DIR}/bin/04-final/bknodeman.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}  \
                                --python-path ${python_path} -b \$LAN_IP -w \"\$WAN_IP\""  || err "install ${module} ${project} failed on host: ${ip}" 
                     emphasize "register ${_project_consul[${target_name},${project}]} consul on host: ${ip}"
                     reg_consul_svc "${_project_consul[${target_name},${project}]}" "${_project_port[${target_name},${project}]}" "${ip}"
        done
    done

    # 注册权限模型
    emphasize "Registration authority model for ${module}"
    bkiam_migrate ${module}

    # 安装openresty
    emphasize "install openresty on host: ${module}"
    "${SELF_DIR}"/pcmd.sh -m ${module}  "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"

    # openresty 服务器上安装consul-template
    emphasize "install consul template on host: ${module}"
    install_consul_template ${module} "${BK_NODEMAN_IP_COMMA}"

    # 启动
    "${SELF_DIR}"/pcmd.sh -m ${module} "systemctl start bk-nodeman.service"

    # nfs
    if [[ ! -z ${BK_NFS_IP_COMMA} ]]; then
        emphasize "mount nfs to host: $BK_NFS_IP0"
        pcmdrc ${module} "_mount_shared_nfs bknodeman"
    fi

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc ${module} "_sign_host_as_module consul-template"

}

install_gse () {
    _install_gse_project $@
}

_install_gse_project () {
    local module=gse
    local project=$1
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    emphasize "add or update appcode: $BK_GSE_APP_CODE"
    add_or_update_appcode "$BK_GSE_APP_CODE" "$BK_GSE_APP_SECRET"
    emphasize "grant mongodb privilege for ${module}"
    grant_mongodb_pri ${module} 
    emphasize "init gse zk nodes on host: $BK_GSE_ZK_ADDR"
    "${SELF_DIR}"/pcmd.sh -H "${BK_ZK_IP0}" "${CTRL_DIR}/bin/create_gse_zk_base_node.sh $BK_GSE_ZK_ADDR"
    "${SELF_DIR}"/pcmd.sh -H "${BK_ZK_IP0}" "${CTRL_DIR}/bin/create_gse_zk_dataid_1001_node.sh"


    # 后续待定分模块部署细节 先全量
    # for project in ${_projects[${module}]};do
    #     emphasize "install ${module}-${project}"
    #     ${SELF_DIR}/pcmd.sh -m ${module} "${CTRL_DIR}/bin/install_gse.sh -e ${CTRL_DIR}/bin/04-final/gse.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}  -b \$LAN_IP"
    # done
    emphasize "install ${module}"
    "${SELF_DIR}"/pcmd.sh -m ${module} "${CTRL_DIR}/bin/install_gse.sh -e ${CTRL_DIR}/bin/04-final/gse.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}  -b \$LAN_IP -w \"\$WAN_IP\""
    for project in gse_task gse_api gse_procmgr gse_data gse_config; do
        reg_consul_svc ${_project_consul["${module},${project}"]} ${_project_port["${module},${project}"]} "${BK_GSE_IP_COMMA}"
    done

    # 启动
    "${SELF_DIR}"/pcmd.sh -m ${module} "systemctl start bk-gse.target"
    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_fta () {
    local module=fta
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    emphasize "install python on host: ${module}"
    install_python $module
    # 注册app_code
    emphasize "add or update appcode ${BK_FTA_APP_CODE}"
    add_or_update_appcode "$BK_FTA_APP_CODE" "$BK_FTA_APP_SECRET"
    # 初始化sql
    emphasize "migrate sql for fta"
    migrate_sql fta
    # 部署后台
    emphasize "install fta on host: ${BK_FTA_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m fta "${CTRL_DIR}/bin/install_fta.sh -b \$LAN_IP -e ${CTRL_DIR}/bin/04-final/fta.env -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH} -m fta"
    emphasize "register ${_project_consul["fta,fta"]}  consul on host: ${_project_ip["fta,fta"]}"
    reg_consul_svc "${_project_consul["fta,fta"]}" "${_project_port["fta,fta"]}" "${_project_ip["fta,fta"]}"

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
}

install_bklog () {
    local module=log
    local target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${SELF_DIR}/bin/default/port.yaml)
    projects=${_projects[${module}]}

    # 初始化sql
    emphasize "migrate sql for ${module}"
    migrate_sql $module 
    emphasize "install python on host: ${module}"
    install_python $module
    # 注册app_code
    emphasize "add or update appocode ${BK_BKLOG_APP_CODE}"
    add_or_update_appcode "$BK_BKLOG_APP_CODE" "$BK_BKLOG_APP_SECRET"

    for project in ${projects[@]}; do
        local python_path=$(get_interpreter_path $module $project)
        IFS="," read -r -a target_server<<<${_project_ip["${target_name},${project}"]}
        for ip in ${target_server[@]}; do
            emphasize "install ${module} ${project} on host: ${ip}"
            cost_time_attention
            if [[ ${python_path} =~ "python" ]]; then
                "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_bklog.sh  -m ${project} --python-path ${python_path} -e ${CTRL_DIR}/bin/04-final/bklog.env -b \$LAN_IP -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
            else
                "${SELF_DIR}"/pcmd.sh -H "${ip}" "${CTRL_DIR}/bin/install_bklog.sh  -m ${project} -e ${CTRL_DIR}/bin/04-final/bklog.env -b \$LAN_IP -s ${BK_PKG_SRC_PATH} -p ${INSTALL_PATH}"
            fi
            emphasize "register ${_project_consul[${target_name},${project}]}  consul on host: ${ip}"
            reg_consul_svc "${_project_consul[${target_name},${project}]}" "${_project_port[${target_name},${project}]}" "${ip}"
    	    emphasize "sign host as module"
    	    pcmdrc "${ip}" "_sign_host_as_module bk${module}-${project}"
        done
    done
}

install_dbcheck () {
    [[ -f ${HOME}/.bkrc ]] && source $HOME/.bkrc
    if ! lsvirtualenv | grep deploy_check > /dev/null 2>&1; then
        emphasize "install dbcheck on host: 中控机"
        "${SELF_DIR}"/bin/install_py_venv_pkgs.sh -e -n deploy_check  \
        -p "/opt/py36/bin/python" \
        -w "${INSTALL_PATH}"/.envs -a "${SELF_DIR}/health_check" \
        -r "${SELF_DIR}/health_check/dbcheck_requirements.txt"
    else
        workon deploy_check && pip install -r "${SELF_DIR}/health_check/dbcheck_requirements.txt"
    fi
}

install_lesscode () {
    local module="lesscode"
    source <(/opt/py36/bin/python ${SELF_DIR}/qq.py -P ${SELF_DIR}/bin/default/port.yaml -p ${BK_PKG_SRC_PATH}/${module}/project.yaml)
    # 注册app_code
    emphasize "add or update appcode ${BK_LESSCODE_APP_CODE}"
    add_or_update_appcode $BK_LESSCODE_APP_CODE $BK_LESSCODE_APP_SECRET
    # 初始化sql
    emphasize "migrate sql for ${module}"
    migrate_sql "${module}"
    # 安装lesscode
    emphasize "install lesscode on host: ${BK_LESSCODE_IP_COMMA}"
    "${SELF_DIR}"/pcmd.sh -m "${module}" "${SELF_DIR}"/bin/install_lesscode.sh -e "${SELF_DIR}"/bin/04-final/lesscode.env \
                            -s "${BK_PKG_SRC_PATH}" -p "${INSTALL_PATH}" 
    emphasize "register ${_project_port["$module,$module"]}  consul server on host: ${BK_LESSCODE_IP_COMMA} "
    reg_consul_svc "${_project_consul["$module,$module"]}" "${_project_port["$module,$module"]}" ${BK_LESSCODE_IP_COMMA}
    # 写入hosts
    emphasize "add lesscode domain to hosts"
    pcmdrc lesscode "add_hosts_lesscode"
    # 注册工作台图标
    emphasize "register lesscode app icon"
    "${SELF_DIR}"/bin/bk-lesscode-reg-paas-app.sh

    # 安装openresty
    emphasize "install openresty on host: ${BK_NGINX_IP_COMMA}"
    ${SELF_DIR}/pcmd.sh -m nginx "${CTRL_DIR}/bin/install_openresty.sh -p ${INSTALL_PATH} -d ${CTRL_DIR}/support-files/templates/nginx/"

    emphasize "install consul template on host: ${BK_NGINX_IP_COMMA}"
    install_consul_template "lesscode" ${BK_NGINX_IP_COMMA} 

    emphasize "sign host as module"
    pcmdrc ${module} "_sign_host_as_module ${module}"
    pcmdrc nginx "_sign_host_as_module consul-template

    emphasize "set bk_lesscode as desktop display by default"
    set_console_desktop "bk_lesscode"
}

install_bkapi () {

    local module=bkapi_check
    emphasize "install consul-template on host: ${BK_APPO_IP_COMMA}"
    install_consul_template ${module} "${BK_NGINX_IP_COMMA}"

    emphasize "install python on hosts: ${BK_NGINX_IP_COMMA}"
    install_python nginx

    emphasize "install bkapi_check for nginx"
    cost_time_attention
    "${CTRL_DIR}"/pcmd.sh -m nginx "${CTRL_DIR}/bin/install_bkapi_check.sh -p ${INSTALL_PATH} -s ${BK_PKG_SRC_PATH} -m ${module}"

}

module=${1:-null}
shift $(($# >= 1 ? 1 : 0))

case $module in
    paas|license|cmdb|job|gse|yum|consul|pypi|bkenv|rabbitmq|zk|mongodb|influxdb|license|cert|nginx|usermgr|appo|bklog|es7|python|appt|kafka|beanstalk|fta|nfs|dbcheck|controller|lesscode|node|bkapi|apigw|etcd|apisix)
        install_"${module}" $@
        ;;
    paas_plugins)
        install_paas_plugins
        ;;
    bkiam|iam)
        install_iam
        ;;
    bkauth|auth)
        install_auth
        ;;
    bkiam_search_engine|iam_search_engine)
        install_iam_search_engine
        ;;
    bknodeman|nodeman) 
        install_nodeman
        ;;
    bkmonitorv3|monitorv3)
        install_bkmonitorv3 "$@"
        ;;
    bkssm|ssm)
        install_ssm
        ;;
    saas-o) 
        install_saas-o "$@"
        ;;
    saas-t)
        install_saas-t "$@"
        ;;
    mysql|redis_sentinel|redis)
        install_"${module}"_common "$@"
        ;;
    null) # 特殊逻辑，兼容source脚本
        ;;
    *)
        echo "$module 不支持"
        exit 1
        ;;
esac
