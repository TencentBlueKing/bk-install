#!/usr/bin/env bash
# vim:ft=sh sts=4 ts=4 sw=4 expandtab nu ai
# set -euo pipefail

CUR_DIR=$(cd ${BASH_SOURCE%/*} 2>/dev/null; pwd)

source ${CUR_DIR}/load_env.sh
source ${CUR_DIR}/functions

get_interpreter_path () {
    local module=$1
    local project=$2
    local is_e=$3
    target_name=$(map_module_name $module)
    source <(/opt/py36/bin/python ${CTRL_DIR}/qq.py -p ${BK_PKG_SRC_PATH}/${target_name}/projects.yaml -P ${CTRL_DIR}/bin/default/port.yaml)
    language=${_language["${target_name},${project}"]}
    if [[ ${language} =~ "python/2" ]]; then
        if ! [[ $is_e == 'false' ]]; then
            install_path=${BK_PY27_ENCRYPT_PATH}
        else
            install_path=${BK_PY27_PATH}
        fi
    elif [[ ${language} =~ "python/3" ]]; then
        if ! [[ $is_e == 'false' ]]; then
            install_path=${BK_PY36_ENCRYPT_PATH}
        else
            install_path=${BK_PY36_PATH}
        fi
    fi
    echo "${install_path}"
}

map_module_name () {
    local module=$1
    case $module in
        log) name=bklog;;
        bkiam|iam)  name=bkiam ;;
        bkiam_search_engine|iam_search_engine)  name=bkiam_search_engine ;;
        ssm|bkssm) name=bkssm;;
        appo|appt) name=paas_agent;;
        monitorv3) name=bkmonitorv3;;
        nodeman) name=bknodeman;;
        saas-o | saas-t ) name=paasagent ;;
        paas ) name=open_paas ;;
        auth|bkauth) name=bkauth;;
        apigw|bkapigw) name=bk_apigateway ;;
        *) name=$module;;
    esac
    echo ${name}
}

grant_mongodb_pri () {
    local module=$1
    local username=BK_${module^^}_MONGODB_USERNAME
    local password=BK_${module^^}_MONGODB_PASSWORD
    ${CTRL_DIR}/pcmd.sh -H $BK_MONGODB_IP0 "${CTRL_DIR}/bin/add_mongodb_user.sh -d ${module} -i mongodb://$BK_MONGODB_ADMIN_USER:$(urlencode $BK_MONGODB_ADMIN_PASSWORD)@\$LAN_IP:27017/admin -u ${!username} -p ${!password}"
}

grant_rabbitmq_pri () {
    local module=$1
    if [[ $module == 'monitorv3' ]];then module='monitor';fi
    username=BK_${module^^}_RABBITMQ_USERNAME
    password=BK_${module^^}_RABBITMQ_PASSWORD
    v_host=BK_${module^^}_RABBITMQ_VHOST
    ${CTRL_DIR}/pcmd.sh -H $BK_RABBITMQ_IP0 "${CTRL_DIR}/bin/add_rabbitmq_user.sh  -u "${!username}" -p "${!password}" -h "${!v_host}""
}

reg_consul_svc () {
    local name=$1
    local port=$2
    # addr: 以逗号分隔的ip字符串
    local addr=$3
    if [[ "$#" -ne 3 ]]; then
        err "注册consul脚本传参错误,可能是模块对应 project.yaml 与脚本配置文件 port.yaml 不匹配."
    fi
    if grep ^[0-9] <<< "$name" > /dev/null; then
        err "注册consul脚本传参错误,第一个参数不应为：$1"
    fi
    # 分割name,tag
    if grep '\.' <<< "${name}" >/dev/null ; then
        n=$(awk -F'.' '{print $2}' <<<${name})
        tag=$(awk -F'.' '{print $1}' <<<${name})
        "${CTRL_DIR}"/pcmd.sh -H ${addr}  "${CTRL_DIR}/bin/reg_consul_svc -n "${n}"  -t ${tag} -p ${port} -a \$LAN_IP -D > /etc/consul.d/service/${n}-${tag}.json && consul reload"
    else
        "${CTRL_DIR}"/pcmd.sh -H ${addr}  "${CTRL_DIR}/bin/reg_consul_svc -n "${name}" -p ${port} -a \$LAN_IP -D > /etc/consul.d/service/${name}.json && consul reload"
    fi
}

add_or_update_appcode () {
    local app_code=$1
    local app_token=$2
    source <(/opt/py36/bin/python ${CTRL_DIR}/qq.py -s -P ${CTRL_DIR}/bin/default/port.yaml)
    paas_login_path=${_project_consul["mysql,paas"]}
    ${CTRL_DIR}/bin/add_or_update_appcode.sh "${app_code}" "${app_token}" "${app_code}" "${paas_login_path}"
}

bkiam_migrate () {
    local module=$1
    local dirname=$(map_module_name $module)
    local app_code=BK_${module^^}_APP_CODE
    local app_token=BK_${module^^}_APP_SECRET
    if [[ $module == 'nodeman' ]]; then
        ${CTRL_DIR}/bin/bkiam_migrate.sh -a "${!app_code}" -s "${!app_token}" -e "${CTRL_DIR}/bin/04-final/bknodeman.env"  ${BK_PKG_SRC_PATH}/${dirname}/support-files/bkiam/*.json
    elif [[ $module == 'monitorv3' ]]; then
        ${CTRL_DIR}/bin/bkiam_migrate.sh -a "$BK_MONITOR_APP_CODE" -s "$BK_MONITOR_APP_SECRET" -e "${CTRL_DIR}/bin/04-final/bkmonitorv3.env"  ${BK_PKG_SRC_PATH}/${dirname}/support-files/bkiam/*.json
    else
        ${CTRL_DIR}/bin/bkiam_migrate.sh -a "${!app_code}" -s "${!app_token}" -e "${CTRL_DIR}/bin/04-final/${module}.env"  ${BK_PKG_SRC_PATH}/${dirname}/support-files/bkiam/*.json
    fi
}

migrate_sql () {
    local module=$1
    source <(/opt/py36/bin/python ${CTRL_DIR}/qq.py -s -P ${CTRL_DIR}/bin/default/port.yaml)
    local name=${_project_consul["mysql,${module}"]}
    local target_dir=$(map_module_name $module)
    if [ ${module} == 'paas' ]; then 
        ${CTRL_DIR}/bin/sql_migrate.sh -n ${name} ${BK_PKG_SRC_PATH}/${target_dir}/support-files/sql/*.sql
        ${CTRL_DIR}/bin/sql_migrate.sh -n ${name} $CTRL_DIR/support-files/sql/0001_ops_*.sql
    elif [ ${module} == 'iam' ]; then
        ${CTRL_DIR}/bin/sql_migrate.sh -n ${name} ${BK_PKG_SRC_PATH}/${target_dir}/support-files/sql/*.sql
        ${CTRL_DIR}/bin/sql_migrate.sh -n ${name} ${BK_PKG_SRC_PATH}/open_paas/support-files/sql/*.sql
    elif [ ${module} == 'job' ]; then
        ${CTRL_DIR}/bin/sql_migrate.sh -n ${name} ${BK_PKG_SRC_PATH}/${target_dir}/support-files/sql/*/*.sql
    else
        ${CTRL_DIR}/bin/sql_migrate.sh -n ${name} ${BK_PKG_SRC_PATH}/${target_dir}/support-files/sql/*.sql
    fi
}

reg_rabbitmq () {
    curl --connect-timeout 10 \
        -H 'Content-Type:application/x-www-form-urlencoded' \
        -X POST \
        -d "mq_ip=rabbitmq.service.consul&username=$BK_RABBITMQ_ADMIN_USER&password=$BK_RABBITMQ_ADMIN_PASSWORD" \
        "http://$BK_PAAS_PRIVATE_ADDR/v1/rabbitmq/init/"
}

grant_mysql_priv () {
    # 如果有project name 那么覆盖第一个参数 为了兼容一个模块多个项目
    local module=$1
    local ip=$2
    local project=${3}
    local mysql_name=default-root
    if ! [ -z $project ]; then
        module="${project}"
    fi
    if ! [ ${module} == 'job' ]; then
        username=BK_${module^^}_MYSQL_USER
    else
        username=BK_${module^^}_MYSQL_USERNAME
    fi
    local password=BK_${module^^}_MYSQL_PASSWORD
    ${CTRL_DIR}/pcmd.sh -H ${BK_MYSQL_IP0} "${CTRL_DIR}/bin/grant_mysql_priv.sh -n ${mysql_name} -u ${!username} -p ${!password} -H ${ip}"
}

_find_all_saas () {
    local saas_pkg_dir=$BK_PKG_SRC_PATH/official_saas

    ls $saas_pkg_dir/bk_*_V*.tar.gz 2>/dev/null | sed 's/_V.*//g;s#^.*/##' | sort -u
}

_find_latest_one () {
    local app_code=$1
    local saas_pkg_dir=$BK_PKG_SRC_PATH/official_saas

    (
        cd "$saas_pkg_dir"
        ls -rt ${app_code}_V*.tar.gz 2>/dev/null | tail -1
    )
}

_find_saas () {
    local app_code=$1
    local app_version=$2
    local saas_pkg_dir=$BK_PKG_SRC_PATH/official_saas

    (
        cd "$saas_pkg_dir"
        ls -rh ${app_code}_V${app_version}*.tar.gz 2>/dev/null | tail -1
    )
}

_find_latest_gse_agent () {
    (
        cd "$BK_PKG_SRC_PATH"
        ls -rt gse_agent_[ce]e-*.tgz 2>/dev/null | tail -1
    )
}

_find_lastet_gse_server () {
    cd "$BK_PKG_SRC_PATH"
    ls -rt gse_[ce]e-*.tgz 2>/dev/null | tail -1
}

pcmdrc () {
    local target=$1
    shift 1
    local content=$@
    local str="source \${CTRL_DIR}/action.rc;source \${CTRL_DIR}/tools.sh;${content[@]}"
    # 根据传入的第一个参数判断pcmd的参数为-m 还是-H
    if [[ $target =~ [0-9]\. ]]; then
        ${CTRL_DIR}/pcmd.sh -H  ${target} "$str"
    else 
        ${CTRL_DIR}/pcmd.sh -m  ${target} "$str"
    fi
}

add_saas_environment () {
    local s

    if [ -f $CTRL_DIR/saas_var.env ]; then
        source $CTRL_DIR/saas_var.env
        for s in $(grep -Po '(?<=declare -A ).*_KV' $CTRL_DIR/saas_var.env); do
            _init_saas_environ ${s%_*}
        done
    fi
}

_init_saas_environ () {
    source <(/opt/py36/bin/python ${CTRL_DIR}/qq.py -s -P ${CTRL_DIR}/bin/default/port.yaml)
    login_path=${_project_consul["mysql,paas"]}
    local app_code=$1
    local EXEC_PAAS_DB="mysql --login-path=${login_path}"
    local k v

    for k in $(eval echo \${!${app_code}_KV[@]}); do
        v=$(eval echo \${${app_code}_KV[$k]})
        $EXEC_PAAS_DB -e "use ${BK_PAAS_MYSQL_NAME};INSERT INTO paas_app_envvars (app_code, mode, name, value, intro) VALUES('$app_code', 'all', '$k', '$v', 'Set by install script') ON DUPLICATE KEY UPDATE value='$v', intro='Update by install script'"
    done
}

add_saas_skip_auth () {
    local base_saas_list=(bk_iam bk_user_manage bk_sops bk_nodeman bk_monitorv3 bk_log_search bk_itsm bk_gsekit bk_apigateway)
    local extra_saas_list=(bk_bcs_app)
    local app_code
    for app_code in "${base_saas_list[@]}" "${extra_saas_list[@]}"; do
        _add_saas_skip_auth "$app_code"
    done
}

_add_saas_skip_auth () {
    source <(/opt/py36/bin/python ${CTRL_DIR}/qq.py -s -P ${CTRL_DIR}/bin/default/port.yaml)
    local login_path=${_project_consul["mysql,paas"]}
    local app_code=$1
    "$CTRL_DIR"/bin/add_skip_auth_appcode.sh "$app_code" "$login_path"
}

wait_return_code () {
    local project=$1
    local timeout=${2:-20}

    case $project in 
        cmdb|gse|paas|bkiam)
            check_scripts=check_${project}.sh
            ;;
        *)
            err "${project} 不支持"
            ;;
    esac

    for i in $(seq "$timeout"); do
        "${CTRL_DIR}"/health_check/"${check_scripts}"  && return 0
        sleep 1
    done
    return 1
}

_mount_shared_nfs () {
    local module=$1
        set -e
        yum -y install nfs-utils
        case $module in
            open_paas)
                local name=$(date +%s)
                # 特殊处理 恢复第一次挂载被删除的文件
                _mount_nfs_partition $module $INSTALL_PATH/public/nfs/$module $INSTALL_PATH/$module/paas/media
                ;;
            job)
                _mount_nfs_partition $module $INSTALL_PATH/public/nfs/$module $INSTALL_PATH/public/$module
                ;;
            paas_agent |appo | appt)
                _mount_nfs_partition $module $INSTALL_PATH/public/nfs/saas $INSTALL_PATH/public/paas_agent/share
                ;;
            bkdata)
                _mount_nfs_partition $module $INSTALL_PATH/public/nfs/$module $INSTALL_PATH/public/$module/nfs
                ;;
            bknodeman)
                _mount_nfs_partition $module $INSTALL_PATH/public/nfs/nodeman $INSTALL_PATH/public/bknodeman
                ;;
        esac
}

_mount_nfs_partition () {
    local module=$1
    local export_dir=$2
    local mount_point=$3

    log "mount nfs shared directory: $mount_point"
    [[ -d $mount_point ]] || mkdir -p $mount_point

    if ! df -P -T | grep "$NFS_IP:$export_dir *nfs. " >/dev/null 2>&1; then
        mount -t nfs -o rw,nolock,nocto,actimeo=3600 $BK_NFS_IP:$export_dir $mount_point || \
            fail "mount NFS directory failed. this may cause error while deploy apps."
    fi

    log "mount nfs director for $module, this may take a while"
    if ! df -P -T | grep "$NFS_IP:$export_dir *nfs. " >/dev/null 2>&1; then
        mount -t nfs -o rw,nolock,actimeo=3600 $BK_NFS_IP0:$export_dir $mount_point || \
            fail "mount NFS directory failed. this may cause error while deploy apps."
    fi

    log "add entry to /etc/fstab: $BK_NFS_IP0:$export_dir -> $mount_point"
    sed -i "/${mount_point//\//\\/}/d" /etc/fstab
    echo "$BK_NFS_IP0:$export_dir $mount_point nfs rw,nolock,actimeo=3600 0 0" >>/etc/fstab
}

_update_common_info () {
    local module="$1"
    step "upgrade version info"
    log "update version info to db"
    _init_version_data  $(map_module_name ${module})
}

_init_version_data () {
    set +u
    local target_mysql="mysql-paas"
    local mycmd="mysql --login-path=${target_mysql}" 
    local MOUDULE="$1"
    declare -A VERSIONS=(
        [bksuite]="蓝鲸智云"
        [open_paas]="PaaS 平台"
        [paas_agent]="PaaS Agent"
        [cmdb]="配置平台"
        [job]="作业平台"
        [gse]="管控平台"
        [usermgr]="用户管理"
        [license]="全局认证服务"
        [bkmonitorv3]="监控平台"
        [bknodeman]="节点管理"
        [bkssm]="凭据管理系统"
        [bkiam]="权限中心"
        [bklog]="日志平台"
        [paas_plugins]="PaaS Plugins"
    )

    if [[ -z "${MOUDULE}" ]]; then
        MOUDULES=( ${!VERSIONS[*]} )
    else
        MOUDULES="${MOUDULE}"
    fi

    for m in "${MOUDULES[@]}"; do 
        TMP=( ${!VERSIONS[@]} )
        for i in "${!TMP[@]}"; do
            if [[ "${TMP[$i]}" = "${m}" ]]; then
                INDEX="$i"
            fi
        done
        VERSION=$(_get_version "${m}")
        let INDEX="${INDEX}"+1
        cat >/tmp/bkv_init_v.sql <<_OO_
        REPLACE INTO production_info VALUES ('$INDEX', '$m', '${VERSIONS[$m]}', '$VERSION');
_OO_
        if [[ "$m" == 'paas_plugins' &&  -z "${VERSION}" ]]; then
            continue 
        else
            $mycmd -e "use bksuite_common; source /tmp/bkv_init_v.sql;"
        fi
    done
    set -u
    [ -f /tmp/bkv_init_v.sql ] && rm -f /tmp/bkv_init_v.sql
}

_get_version () {
    local module=$1

    if [ "$module" == 'bksuite' ]; then
        cat "$BK_PKG_SRC_PATH"/VERSION
        return 0
    fi
    if [ -f "$BK_PKG_SRC_PATH/$module"/VERSION ]; then
        cat "$BK_PKG_SRC_PATH/$module"/VERSION
        return 0
    fi
}

get_common_bk_service_status (){
    local module=$1
    shift
    local service=()
    export FORCE_TTY=1
    for p in "$@"; do  
        p=${p/-/_}   # 兼容返回分隔符
        service+=( "bk-${module}-${p#${module}_}.service" )
    done
    "${CTRL_DIR}"/bin/bks.sh "${service[@]}"
} 

get_spic_bk_service_status (){
    local module=$1
    shift
    local service=()
    export FORCE_TTY=1
    for p in "$@"; do  
        if [[ "${module}"  == 'paas' && $#  != 1 ]]; then
            service+=( "bk-${p#${module}_}.service" )
        else
            service+=( "bk-${p#${module}_}.service" )
        fi
    done
    "${CTRL_DIR}"/bin/bks.sh "${service[@]}"
} 

get_docker_service_status (){
    local module=$1
    local service=${2:-}
    if [[ "$service" != '' ]]; then
        container_name="bk-${module}-${service}"
    else
        container_name="bk-${module}-.*"
    fi
    "${CTRL_DIR}"/bin/check_containers_status.sh "${container_name}"
}

get_service_status () {
    local service=()
    export FORCE_TTY=1
    for p in "$@"; do  
        service+=( "${p}.service" )
    done
    "${CTRL_DIR}"/bin/bks.sh "${service[@]}"
}

_sign_host_as_module () {
    # 参数, 标记本机安装的服务
    local name=$1
    sign_file=$INSTALL_PATH/.installed_module

    if [ "$1" == "" ]; then
        warn "$FUNCNAME: nothing going to add, need more arguments"
        warn ""
        return 0
    fi

    mkdir -p ${sign_file%/*}
    if [ ! -f $sign_file ]; then
        echo $name >$sign_file
    else
        if ! grep -Eq "^$name\b" $sign_file; then
            echo $name >>$sign_file
        fi
    fi
}

_find_node_latest () {
    local node_dir="$BK_PKG_SRC_PATH"
    (
        cd "$node_dir";ls -rt node-v*-linux-x64.tar.gz 2>/dev/null | tail -1
    )
}

add_hosts_lesscode () {
    local lesscode_hostname="${BK_LESSCODE_PUBLIC_ADDR%:*}"
    local paas_hostname="${BK_PAAS_PUBLIC_ADDR%:*}"
    
    sed -i "/$lesscode_hostname/d" /etc/hosts
    echo "$LAN_IP $lesscode_hostname" >> /etc/hosts
    sed -i "/$paas_hostname/d" /etc/hosts
    echo "$BK_NGINX_IP $paas_hostname" >> /etc/hosts
}

set_console_desktop () {
    local app_code=$1
    local user=${2:-admin}
    local db=open_paas
    local table=paas_app


    # 默认将所有蓝鲸app展示在桌面
    if ! [[ $app_code == "bk_iam" ]]; then
        if ! mysql -h"$BK_MYSQL_IP" -u"$BK_MYSQL_ADMIN_USER" -p"$BK_MYSQL_ADMIN_PASSWORD" -e "update $db.$table set is_default=if(is_default=0, 1, is_default) where code='$app_code';" &>/dev/null; then
            err "Failed to set up desktop app: $app_code "
        fi
        # 默认将所有部署的应用展示在admin的桌面
        "${CTRL_DIR}"/pcmd.sh -H "$BK_PAAS_IP0" "workon open_paas-console; export BK_ENV=\"production\"; export BK_FILE_PATH=\"$INSTALL_PATH/open_paas/cert/saas_priv.txt\";python manage.py add_app_to_desktop --app_code=\"$app_code\" --username=\"$user\"" &>/dev/null
    fi
   
}

sync_secret_to_bkauth ()  {
    "${CTRL_DIR}"/pcmd.sh -H "$BK_AUTH_IP0" "$INSTALL_PATH/bkauth/bin/bkauth sync -c $INSTALL_PATH/etc/bkauth_config.yaml"
}