#!/usr/bin/env bash
 
# 安全模式
MODULES=(nodeman nginx paasagent)
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

source "${SELF_DIR}"/../load_env.sh


usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -m, --module      [必选] "安装的子模块(${PROJECTS[*]})" ]
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
            MODULE=$1
            ;;
        --help | -h | '-?' )
            echo ${MODULES[*]}
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

if ! rpm -q consul-template >/dev/null;then
    yum install -y consul-template
fi


if ! [ -z $MODULE ];then
    if [[ $MODULE == 'nginx' ]];then
        consul kv put bkcfg/global/bk_home "$BK_HOME"
        consul kv put bkcfg/global/bk_http_schema "$BK_HTTP_SCHEMA"
        consul kv put bkcfg/ports/paas_http ${BK_PAAS_PUBLIC_ADDR##*:}
        consul kv put bkcfg/ports/paas_https 443
        consul kv put bkcfg/fqdn/paas "${BK_PAAS_PUBLIC_ADDR%%:*}"
        consul kv put bkcfg/domain/paas "${BK_PAAS_PRIVATE_ADDR%%:*}"
        # cmdb
        consul kv put bkcfg/fqdn/cmdb "${BK_CMDB_PUBLIC_ADDR%%:*}"
        # job
        consul kv put bkcfg/fqdn/job $(awk -F'[:/]' '{ print $4}' <<<"${BK_JOB_PUBLIC_URL}")
        consul kv put bkcfg/fqdn/jobapi $(awk -F'[:/]' '{ print $4}' <<<"${BK_JOB_API_PUBLIC_URL}")
        consul kv put bkcfg/ports/job_gateway_http "$BK_JOB_GATEWAY_SERVER_HTTP_PORT"
        # nodeman
        consul kv put bkcfg/fqdn/nodeman $(awk -F'[:/]' '{ print $4}' <<<"${BK_NODEMAN_PUBLIC_DOWNLOAD_URL}")
        rsync -a  ${SELF_DIR}/../support-files/templates/nginx/*.conf /etc/consul-template/templates/
        rsync -a  ${SELF_DIR}/../support-files/templates/nginx/app_upstream.conf.tpl /etc/consul-template/templates/
        #apigw
        consul kv put bkcfg/fqdn/bkapi $(awk -F'[:/]' '{ print $4}' <<<"${BK_APIGW_API_PUBLIC_URL}")
        consul kv put bkcfg/fqdn/apigw $(awk -F'[:/]' '{ print $4}' <<<"${BK_APIGW_PUBLIC_URL}")
        cat <<'EOF' > /etc/consul-template/conf.d/paas.conf
template {
  source = "/etc/consul-template/templates/paas.conf"
  destination = "/usr/local/openresty/nginx/conf/conf.d/paas.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && echo reload openresty && systemctl reload openresty'"
  command_timeout = "10s"
}
EOF
        cat <<'EOF' > /etc/consul-template/conf.d/app_upstream.conf
template {
  source = "/etc/consul-template/templates/app_upstream.conf.tpl"
  destination = "/usr/local/openresty/nginx/conf/conf.d/app_upstream.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && systemctl reload openresty || true'"
  command_timeout = "10s"
}
EOF

        cat <<'EOF' > /etc/consul-template/conf.d/cmdb.conf
template {
  source = "/etc/consul-template/templates/cmdb.conf"
  destination = "/usr/local/openresty/nginx/conf/conf.d/cmdb.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && systemctl reload openresty || true'"
  command_timeout = "10s"
}
EOF

        cat <<'EOF' > /etc/consul-template/conf.d/job.conf
template {
  source = "/etc/consul-template/templates/job.conf"
  destination = "/usr/local/openresty/nginx/conf/conf.d/job.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && systemctl reload openresty || true'"
  command_timeout = "10s"
}
EOF

        cat <<'EOF' > /etc/consul-template/conf.d/apigw.conf
template {
  source = "/etc/consul-template/templates/apigw.conf"
  destination = "/usr/local/openresty/nginx/conf/conf.d/apigw.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && systemctl reload openresty || true'"
  command_timeout = "10s"
}
EOF
    elif [[ ${MODULE} == 'nodeman' ]];then
        rsync -a  ${SELF_DIR}/../support-files/templates/nginx/nodeman.conf /etc/consul-template/templates/
        cat <<'EOF' > /etc/consul-template/conf.d/nodeman.conf
template {
  source = "/etc/consul-template/templates/nodeman.conf"
  destination = "/usr/local/openresty/nginx/conf/conf.d/nodeman.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && systemctl reload openresty || true'"
  command_timeout = "10s"
}
EOF
        if [[ ! -z "${WAN_IP}" ]]; then
            if  [[ "$WAN_IP" =~ ^[0-9.]+$ ]]; then
                consul kv put bkcfg/global/nodeman_wan_ip "${WAN_IP}"
            fi
        fi
    elif [[ $MODULE == 'paasagent' ]];then
        consul kv put bkcfg/ports/paasagent 8010
        rsync -a  ${SELF_DIR}/../support-files/templates/nginx/paasagent.conf /etc/consul-template/templates/
        cat <<'EOF' > /etc/consul-template/conf.d/paasagent.conf
template {
  source = "/etc/consul-template/templates/paasagent.conf"
  destination = "/usr/local/openresty/nginx/conf/conf.d/paasagent.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && systemctl reload openresty || true'"
  command_timeout = "10s"
}
EOF
    elif [[ $MODULE == 'lesscode' ]]; then 
        consul kv put bkcfg/global/lesscode_port "${BK_LESSCODE_PORT}"
        consul kv put bkcfg/domain/lesscode "${BK_LESSCODE_PUBLIC_ADDR%%:*}"
        rsync -avz  ${SELF_DIR}/../support-files/templates/nginx/lesscode.conf /etc/consul-template/templates/
        cat <<'EOF' > /etc/consul-template/conf.d/lesscode.conf
template {
  source = "/etc/consul-template/templates/lesscode.conf"
  destination = "/usr/local/openresty/nginx/conf/conf.d/lesscode.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && systemctl reload openresty || true'"
  command_timeout = "10s"
}
EOF
    elif [[ $MODULE == 'bkapi_check' ]]; then
        consul kv put bkcfg/fqdn/bkapi_check $(awk -F'[:/]' '{ print $4}' <<<"${BK_API_CHECK_PUBLICE_URL}")
        cat <<'EOF' > /etc/consul-template/conf.d/bkapi_check.conf
template {
  source = "/etc/consul-template/templates/bkapi_check.conf"
  destination = "/usr/local/openresty/nginx/conf/conf.d/bkapi_check.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && systemctl reload openresty || true'"
  command_timeout = "10s"
}
EOF
    fi
    rsync -avz  ${SELF_DIR}/../support-files/templates/nginx/nginx.conf /etc/consul-template/templates/
    cat <<'EOF' > /etc/consul-template/conf.d/nginx.conf
template {
  source = "/etc/consul-template/templates/nginx.conf"
  destination = "/usr/local/openresty/nginx/conf/nginx.conf"
  command = "/bin/sh -c '/usr/local/openresty/nginx/sbin/nginx -t && echo reload openresty && systemctl reload openresty'"
  command_timeout = "10s"
}
EOF


fi

systemctl enable consul-template
systemctl start consul-template
