#!/usr/bin/env bash
# 用途： 安装蓝鲸的paas_plugins
 
# 安全模式
# set -euo pipefail 


# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0


# 全局默认变量
# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

# PYTHON目录
PYTHON_PATH=/opt/py27/bin/python

RPM_DEP=(mysql-devel gcc libevent-devel git svn nfs-utils)

MODULE="paas_plugins"
PROJECTS=(paas appo appt)
APP_LOG_AGENT_PROJECTS=(django component uwsgi celery java)
PAAS_LOG_AGENT_PROJECTS=(paas_esb_api bkapigateway_esb_api bkapigateway_apigateway_api)


APP_ENV="appo"
LAN_IP= 
BK_PAAS_IP0=

# 导入LAN_IP BK_PAAS_IP
source ${SELF_DIR}/02-dynamic/hosts.env
source /etc/blueking/env/local.env

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -m, --module      [必选] "安装的子模块(${PROJECTS[*]})" ]
            [ -a, --app-env     [可选] "部署的环境" ]
            [ --python-path     [可选] "指定创建virtualenv时的python二进制路径，默认为/opt/py27/bin/python" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]
            [ -s, --srcdir      [必填] "从该目录拷贝$MODULE/project目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --log-dir         [可选] "日志目录,默认为\$PREFIX/logs/$MODULE" ]
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
        -m | --module )
            shift
            PAAS_PLUGINS_MODULE=$1
            ;;
        --python-path )
            shift
            PYTHON_PATH=$1
            ;;
        -e | --env-file)
            shift
            ENV_FILE="$1"
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        -a | --app-env )
            shift
            APP_ENV=$1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
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
LOG_DIR=${LOG_DIR:-$PREFIX/logs/$MODULE}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/$MODULE ]]; then
    warning "$MODULE_SRC_DIR/$MODULE 不存在"
fi
if [[ $PAAS_PLUGINS_MODULE = "paas" ]]; then
    if ! [[ $("$PYTHON_PATH" --version 2>&1) = *Python* ]]; then
        warning "$PYTHON_PATH 不是一个合法的python二进制"
    fi
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if [[ -z ${PAAS_PLUGINS_MODULE} ]];then
    warning "-m 参数不可为空"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; } 

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"
install -o blueking -g blueking -m 755 -d "$PREFIX/public/$MODULE"
install -o blueking -g blueking -m 755 -d /var/run/${MODULE}

# 配置/var/run临时目录重启后继续生效
cat > /etc/tmpfiles.d/${MODULE}.conf <<EOF
D /var/run/${MODULE} 0755 blueking blueking
EOF

if [[ $APP_ENV == 'appo' ]];then 
    BK_PAAS_AGENT_ENV="PRODUCT"
elif [[ $APP_ENV == 'appt' ]];then 
    BK_PAAS_AGENT_ENV="TEST"
fi

case ${PAAS_PLUGINS_MODULE} in 
    paas)
         # 必须安装在paas_ip0
        rsync -aL ${MODULE_SRC_DIR}/${MODULE}/log_parser ${PREFIX}/${MODULE}/
        rsync -aL ${MODULE_SRC_DIR}/${MODULE}/log_agent ${PREFIX}/${MODULE}/
        rsync -aL ${MODULE_SRC_DIR}/${MODULE}/log_alert ${PREFIX}/${MODULE}/
        chown -R blueking.blueking  ${PREFIX}/${MODULE}
        if rpm -ql logstash > /dev/null 2>&1; then
            rpm -e logstash
        fi
        set +e
        rpm -ivh ${MODULE_SRC_DIR}/${MODULE}/support-files/pkgs/logstash-7.16.1-x86_64.rpm  \
                || error "install logstash failed."
        set -e

        if rpm -ql filebeat >/dev/null;then rpm -e filebeat;fi 
        if ! rpm -ql filebeat >/dev/null;then
            rpm -ivh ${MODULE_SRC_DIR}/${MODULE}/support-files/pkgs/filebeat-5.2.0-x86_64.rpm
        fi

        "${SELF_DIR}"/install_py_venv_pkgs.sh -n "log_alert" \
           -p "${PYTHON_PATH}" \
           -w "${PREFIX}/.envs" -a "$PREFIX/$MODULE/log_alert" \
           -r "$MODULE_SRC_DIR/$MODULE/log_alert/requirements.txt" \
           -s "$MODULE_SRC_DIR/$MODULE/support-files/pkgs"

        if [[ "${LAN_IP}" ==  ${BK_PAAS_IP0} ]];then
            "$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
                -e "$ENV_FILE" -E BK_PAAS_AGENT_ENV=" "\
                $MODULE_SRC_DIR/$MODULE/support-files/templates/log_agent#* \
                $MODULE_SRC_DIR/$MODULE/support-files/templates/*log_agent.conf \
                $MODULE_SRC_DIR/$MODULE/support-files/templates/*log_agent_paas.conf \
                $MODULE_SRC_DIR/$MODULE/support-files/templates/*log_parser* \
                $MODULE_SRC_DIR/$MODULE/support-files/templates/*log_alert*
        else
            "$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
                -e "$ENV_FILE" -E BK_PAAS_AGENT_ENV=" "\
                $MODULE_SRC_DIR/$MODULE/support-files/templates/log_agent#* \
                $MODULE_SRC_DIR/$MODULE/support-files/templates/*log_agent.conf \
                $MODULE_SRC_DIR/$MODULE/support-files/templates/*log_agent_paas.conf \
                $MODULE_SRC_DIR/$MODULE/support-files/templates/*log_parser*
        fi

        # log agent paas
        cat > /lib/systemd/system/bk-filebeat@.service <<EOF
[Unit]
Description="BlueKing paas plugins filebeat"
After=network-online.target
PartOf=blueking.target bk-filebeat.target 

[Service]
ExecStart=/usr/share/filebeat/bin/filebeat -c ${PREFIX}/${MODULE}/log_agent/conf/%i.yml
Restart=always
RestartSec=3s

[Install]
WantedBy=bk-filebeat.target blueking.target
EOF
        cat > /usr/lib/systemd/system/bk-filebeat.target <<EOF
[Unit]
Description=BlueKing PaaS Plugins target allowing to start/stop all PaaS Plugins filebeat module instances at once

[Install]
WantedBy=multi-user.target
EOF
        # log parse
        cat > /usr/lib/systemd/system/bk-logstash.target <<EOF
[Unit]
Description=BlueKing PaaS Plugins target allowing to start/stop all PaaS Plugins logstash module instances at once

[Install]
WantedBy=multi-user.target
EOF
        cat > /lib/systemd/system/bk-logstash-paas-app-log.service <<EOF
[Unit]
Description="BlueKing paas plugins logstash"
After=network-online.target
PartOf=blueking.target bk-logstash.target 

[Service]
Environment=LS_JAVA_HOME=${PREFIX}/jvm/
ExecStart=/usr/share/logstash/bin/logstash -f ${PREFIX}/paas_plugins/log_parser/conf/paas_app_log.conf
Restart=always
RestartSec=3s

[Install]
WantedBy=bk-logstash.target blueking.target
EOF
        cat > /lib/systemd/system/bk-logstash-paas-log.service <<EOF
[Unit]
Description="BlueKing paas plugins logstash"
After=network-online.target
PartOf=blueking.target bk-logstash.target 

[Service]
Environment=LS_JAVA_HOME=${PREFIX}/jvm/
ExecStart=/usr/share/logstash/bin/logstash -f ${PREFIX}/paas_plugins/log_parser/conf/paas_log.conf --path.data ${PREFIX}/paas_plugins/log_parser/data/paas_log/ 
Restart=always
RestartSec=3s

[Install]
WantedBy=bk-logstash.target blueking.target
EOF

        cat > /lib/systemd/system/bk-logstash-apigw-log.service <<EOF
[Unit]
Description="BlueKing apigw plugins logstash"
After=network-online.target
PartOf=blueking.target bk-logstash.target 

[Service]
Environment=LS_JAVA_HOME=${PREFIX}/jvm/
ExecStart=/usr/share/logstash/bin/logstash -f ${PREFIX}/paas_plugins/log_parser/conf/bkapigateway_log.conf --path.data ${PREFIX}/paas_plugins/log_parser/data/bkapigateway_log
Restart=always
RestartSec=3s

[Install]
WantedBy=bk-logstash.target blueking.target
EOF

        # log alert
        if [[ ${LAN_IP} == ${BK_PAAS_IP0} ]];then
        cat > /usr/lib/systemd/system/bk-paas-plugins-log-alert.service <<EOF
[Unit]
Description=BlueKing PaaS Plugins log alert
After=network-online.target
PartOf=blueking.target bk-paasplugins.target

[Service]
Type=simple
User=blueking
Group=blueking
WorkingDirectory=$PREFIX/${MODULE}/log_alert
Environment=ENV=production
Environment=LOGGING_DIR=${PREFIX}/logs/paas_plugins
ExecStart=${PREFIX}/.envs/log_alert/bin/python run.py
Restart=on-failure
RestartSec=3s
KillSignal=SIGQUIT
LimitNOFILE=204800

[Install]
WantedBy=bk-paas-plugins.target blueking.target
EOF
        systemctl enable bk-paas-plugins-log-alert.service
        fi
        for pro in ${PAAS_LOG_AGENT_PROJECTS[@]};do
            systemctl enable bk-filebeat@${pro}.service
        done
        systemctl enable bk-logstash-paas-app-log.service
        systemctl enable bk-logstash-paas-log.service
        systemctl enable bk-logstash-apigw-log 
        ;;
    appo|appt)
        rsync -aL ${MODULE_SRC_DIR}/${MODULE}/log_agent ${PREFIX}/${MODULE}/
        # if ! grep -qEw 'paas_agent|appo|appt' ${PREFIX}/.install_module; then
        #     if ! grep -qEw 'paas|open_paas' ${PREFIX}/.install_module; then
        #         error "open_paas/appt/appo does not installed on this host successfully."
        #     fi
        # fi
        # log agent must be installed on the same machine with paas_agent
        if rpm -ql filebeat >/dev/null;then rpm -e filebeat;fi 

        if ! rpm -ql filebeat >/dev/null;then
            rpm -ivh ${MODULE_SRC_DIR}/${MODULE}/support-files/pkgs/filebeat-5.2.0-x86_64.rpm
        fi
        "$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
            -E BK_PAAS_AGENT_ENV="$BK_PAAS_AGENT_ENV" -e "$ENV_FILE" \
            $MODULE_SRC_DIR/$MODULE/support-files/templates/log_agent#* \
            $MODULE_SRC_DIR/$MODULE/support-files/templates/*log_agent.conf
            # 生成service定义配置
        cat > /lib/systemd/system/bk-filebeat@.service <<EOF
[Unit]
Description="BlueKing paas plugins filebeat"
After=network-online.target
PartOf=blueking.target bk-filebeat.target 

[Service]
ExecStart=/usr/share/filebeat/bin/filebeat -c ${PREFIX}/${MODULE}/log_agent/conf/%i.yml
Restart=always
RestartSec=3s

[Install]
WantedBy=bk-filebeat.target blueking.target
EOF
        cat > /usr/lib/systemd/system/bk-filebeat.target <<EOF
[Unit]
Description=BlueKing PaaS Plugins target allowing to start/stop all PaaS Plugins filebeat module instances at once

[Install]
WantedBy=multi-user.target
EOF
        for pro in ${APP_LOG_AGENT_PROJECTS[@]};do
            systemctl enable bk-filebeat@${pro}.service
        done
        ;;
esac