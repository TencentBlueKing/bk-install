#!/usr/bin/env bash
# shellcheck disable=SC1090

# 读入基础配置
SELF_DIR=$(dirname "$(readlink -f "$0")")

#####
# 自动协助生成变量
#################

# 输入：cert/passwd.txt
# 输出：作业平台需要的通信用的ssl证书密码
gen_cert_passwd_var () {
    local gse_pass job_pass
    if [[ -d $BK_CERT_PATH ]];then
        gse_pass=$(awk '$1 == "gse_job_api_client.p12" {print $NF}' "$BK_CERT_PATH"/passwd.txt)
        job_pass=$(awk '$1 == "job_server.p12" {print $NF}' "$BK_CERT_PATH"/passwd.txt)
    else
        source ~/.bkrc
        gse_pass=$(awk '$1 == "gse_job_api_client.p12" {print $NF}' "$BK_PKG_SRC_PATH"/cert/passwd.txt)
        job_pass=$(awk '$1 == "job_server.p12" {print $NF}' "$BK_PKG_SRC_PATH"/cert/passwd.txt)
    fi
    if [[ -z $BK_GSE_SSL_KEYSTORE_PASSWORD || -z $BK_JOB_GATEWAY_SERVER_SSL_TRUSTSTORE_PASSWORD ]]; then
        cat <<EOF
BK_GSE_SSL_KEYSTORE_PASSWORD='$gse_pass'
BK_GSE_SSL_TRUSTSTORE_PASSWORD='$gse_pass'
BK_JOB_GATEWAY_SERVER_SSL_KEYSTORE_PASSWORD='$job_pass'
BK_JOB_GATEWAY_SERVER_SSL_TRUSTSTORE_PASSWORD='$job_pass'
EOF
    fi
}

gen_job_spring_cloud_security_pair () {
    local rsa_private_key rsa_public_key
    if [[ -z "$BK_JOB_SECURITY_PRIVATE_KEY_BASE64" || -z "$BK_JOB_SECURITY_PUBLIC_KEY_BASE64" ]]; then
        # 原始的RSA私钥, 需要为PKCS#8封装.
        rsa_private_key=$(openssl genrsa 2048 2>/dev/null | openssl pkcs8 -nocrypt -topk8 2>/dev/null)
        # 基于私钥生成公钥
        rsa_public_key=$(openssl rsa -pubout 2>/dev/null <<< "$rsa_private_key")
        if [[ -z "$rsa_private_key" || -z "$rsa_public_key" ]]; then
            return 0
        else
            cat <<EOF
BK_JOB_SECURITY_PRIVATE_KEY_BASE64='$(base64 -w0 <<<"$rsa_private_key")'
BK_JOB_SECURITY_PUBLIC_KEY_BASE64='$(base64 -w0 <<<"$rsa_public_key")'
EOF
        fi
    fi
}

# APP_CODE & APP_TOKEN
gen_app_token_def () {
    local code k v
    code=$1
    k=${code^^}_APP_CODE
    v=${code^^}_APP_SECRET
    if [[ -z "${!k}" || -z "${!v}" ]]; then
    cat <<EOF
$k=$code
$v=$(uuid -v4)
EOF
    fi
}

# 获取esb的publickey
get_esb_publickey_in_base64 () {
    local app_code=$1
    local app_token=$2
    curl -s  "http://paas.service.consul/api/c/compapi/v2/esb/get_api_public_key/?bk_app_code=$app_code&bk_app_secret=$app_token&bk_username=admin" \
    | jq -r .data.public_key | base64 -w0
}

gen_mysql_password () {
    local prefix=${1^^}
    local password=$2
    local k=${prefix}_MYSQL_PASSWORD
    if [[ -z "${!k}" ]]; then
        cat <<EOF
$k='$password'
EOF
    fi
}

gen_rabbitmq_password () {
    local prefix=${1^^}
    local password=$2
    local k=${prefix}_RABBITMQ_PASSWORD
    if [[ -z "${!k}" ]]; then
        cat <<EOF
$k='$password'
EOF
    fi
}

gen_redis_password () {
    local prefix=${1^^}
    local password=$2
    local k=${prefix}_REDIS_PASSWORD
    local tmp=${prefix/BK_/}
    local y=BK_REDIS_${tmp}_IP0
    local z=BK_REDIS_SENTINEL_${tmp}_IP0
    if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then 
        source "$SELF_DIR"/01-generate/dbadmin.env
    fi
    if [[ -r "$SELF_DIR"/02-dynamic/hosts.env ]]; then 
        source "$SELF_DIR"/02-dynamic/hosts.env
    fi
    if [[ -z ${!y} && -z ${!z} ]];then
        cat <<EOF
$k=$BK_REDIS_ADMIN_PASSWORD
EOF
    else
        if [[ -z "${!k}" ]]; then
            cat <<EOF
$k='$password'
EOF
        fi
    fi
}

# random password
# default length: 12
# default character list: [[:alnum:]] + '_'
# Usage: rndpw 20 $'!@#$%^<>()[]'
rndpw () {
    tr -dc _A-Za-z0-9"$2" </dev/urandom | head -c"${1:-12}"
}


case $1 in 
    paas_plugins)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/paas_plugins.env ]]; then
            source "$SELF_DIR"/04-final/paas_plugins.env
        fi
        # 跟paas共用单节点redis
        if [[ -z "$BK_PAAS_PLUGINS_REDIS_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_PAAS_PLUGINS_REDIS_PASSWORD" "$BK_REDIS_ADMIN_PASSWORD"
        fi
        if [[ -z "$BK_PAAS_PLUGINS_ES7_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_PAAS_PLUGINS_ES7_PASSWORD" "$BK_ES7_ADMIN_PASSWORD"
        fi
        ;;
    usermgr)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/usermgr.env ]]; then
            source "$SELF_DIR"/04-final/usermgr.env
        fi
        str=$(gen_app_token_def bk_usermgr)
        eval "$str"
        [[ -n "$str" ]] && echo "$str"

        # paas的管理员密码
        if [[ -z $BK_PAAS_ADMIN_PASSWORD ]]; then
            printf "%s=%q\n" "BK_PAAS_ADMIN_PASSWORD" "$(rndpw 12)"
        fi
        gen_mysql_password BK_USERMGR "$(rndpw 12)"
        gen_rabbitmq_password BK_USERMGR "$(rndpw 12)"
        if [[ -z "$BK_USERMGR_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_USERMGR_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        ;;
    paas)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/paas.env ]]; then
            source "$SELF_DIR"/04-final/paas.env
        fi
        if [[ -z $BK_PAAS_ESB_SECRET_KEY ]]; then
            printf "%s=%q\n" "BK_PAAS_ESB_SECRET_KEY" "$(rndpw 51)"
        fi
        # paas的app_code是代码写死为bk_paas/bk_console/bk_paas_plugins等，但是需要对应同样的APP_SECRET
        str=$(gen_app_token_def bk_paas)
        eval "$str"
        [[ -n "$str" ]] && echo "$str"
        if [[ -z "$BK_PAAS_REDIS_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_PAAS_REDIS_PASSWORD" "$BK_REDIS_ADMIN_PASSWORD"
        fi
        gen_mysql_password BK_PAAS "$(rndpw 12)"

        if [[ -z "$BK_PAAS_ES7_ADDR" ]];then
            printf "%s=%q\n" "BK_PAAS_ES7_ADDR" "elastic:${BK_ES7_ADMIN_PASSWORD}@es7.service.consul:9200"
        fi
        ;;
    cmdb) 
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/cmdb.env ]]; then
            source "$SELF_DIR"/04-final/cmdb.env
        fi
        str=$(gen_app_token_def bk_cmdb)
        eval "$str"
        [[ -n "$str" ]] && echo "$str"

        if [[ -z "$BK_CMDB_MONGODB_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_CMDB_MONGODB_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_CMDB_EVENTS_MONGODB_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_CMDB_EVENTS_MONGODB_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_CMDB_REDIS_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_CMDB_REDIS_PASSWORD" "$BK_REDIS_ADMIN_PASSWORD"
        fi
#        gen_redis_password BK_CMDB "$(rndpw 12)"
        if [[ -z "$BK_CMDB_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_CMDB_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        ;;
    gse)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/gse.env ]]; then
            source "$SELF_DIR"/04-final/gse.env
        fi
        str=$(gen_app_token_def bk_gse)
        eval "$str"
        [[ -n "$str" ]] && echo "$str"
        redis_password=$(rndpw 12)

        if [[ -z "$BK_GSE_MONGODB_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_GSE_MONGODB_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_GSE_REDIS_PASSWORD" ]]; then
            gen_redis_password "BK_GSE" "${redis_password}"
        fi
        if [[ -z "$BK_GSE_ZK_AUTH" ]]; then
            printf "%s=%q\n" "BK_GSE_ZK_AUTH" "zkuser:$(rndpw 12)"
        fi
        ;;
    job) 
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/job.env ]]; then
            source "$SELF_DIR"/04-final/job.env
        fi
        str=$(gen_app_token_def bk_job)
        eval "$str"
        [[ -n "$str" ]] && echo "$str"
        #get_esb_publickey_in_base64 "$BK_JOB_APP_CODE" "$BK_JOB_APP_SECRET"
        gen_job_spring_cloud_security_pair
        if [[ -z "$BK_JOB_SECURITY_PASSWORD" ]]; then
            echo "BK_JOB_SECURITY_PASSWORD=$(rndpw 8)"
        fi
        gen_cert_passwd_var

        # 存储依赖的密码,主要是为了让JOB各个模块的密码保持一致。
        mysql_password=$(rndpw 12)
        rabbitmq_password=$(rndpw 12)

        for m in BK_JOB_MANAGE BK_JOB_EXECUTE BK_JOB_CRONTAB BK_JOB_BACKUP BK_JOB_ANALYSIS; do
            gen_mysql_password "$m" "$mysql_password"
            gen_rabbitmq_password "$m" "$rabbitmq_password"
            gen_redis_password "$m" "$BK_REDIS_ADMIN_PASSWORD"
        done

        #mongod(新增的)
        if [[ -z "$BK_JOB_LOGSVR_MONGODB_URI" ]]; then
            printf "%s=%s\n" "BK_JOB_LOGSVR_MONGODB_URI" "mongodb://joblog:$(rndpw 8 )@mongodb-job.service.consul:27017/joblog?replicaSet=rs0"
        fi

        # actuator密码（获取metrics等信息）
        if [[ -z "$BK_JOB_ACTUATOR_PASSWORD" ]]; then
            printf "%s=%s\n" BK_JOB_ACTUATOR_PASSWORD "$(rndpw 12)"
        fi

        # 对称加密encryp key密钥
        if [[ -z "$BK_JOB_ENCRYPT_PASSWORD" ]]; then
            printf "%s=%s\n" BK_JOB_ENCRYPT_PASSWORD "$(rndpw 16)"
        fi
        if [[ -z "$BK_JOB_MANAGE_SERVER_HOST0" ]]; then
            printf "%s=%q\n" "BK_JOB_MANAGE_SERVER_HOST0" "$BK_JOB_IP0"
        fi
        if [[ -z "$BK_JOB_MANAGE_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_JOB_MANAGE_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        if [[ -z "$BK_JOB_EXECUTE_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_JOB_EXECUTE_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        if [[ -z "$BK_JOB_CRONTAB_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_JOB_CRONTAB_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        if [[ -z "$BK_JOB_BACKUP_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_JOB_BACKUP_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        if [[ -z "$BK_JOB_ANALYSIS_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_JOB_ANALYSIS_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        ;;
    bkssm)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/bkssm.env ]]; then
            source "$SELF_DIR"/04-final/bkssm.env
        fi
        if [[ -z "$BK_SSM_ACCESS_TOKEN" ]]; then
            printf "%s=%q\n" "BK_SSM_ACCESS_TOKEN" "$(rndpw 32)"
        fi
        if [[ -z "$BK_SSM_MYSQL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_SSM_MYSQL_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_SSM_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_SSM_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        if [[ -z "$BK_SSM_REDIS_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_SSM_REDIS_PASSWORD" "$BK_REDIS_ADMIN_PASSWORD"
        fi
        ;;
    bkauth)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/bkauth.env ]]; then
            source "$SELF_DIR"/04-final/bkauth.env
        fi
        if [[ -z "$BK_AUTH_PPROF_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_AUTH_PPROF_PASSWORD" "$(rndpw 32)"
        fi
        if [[ -z "$BK_AUTH_ENCRYPT_KEY" ]]; then
            printf "%s=%q\n" "BK_AUTH_ENCRYPT_KEY" "$(tr -dc A-Za-z0-9"$2" </dev/urandom | head -c"32")"
        fi
        if [[ -z "$BK_AUTH_MYSQL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_AUTH_MYSQL_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_AUTH_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_AUTH_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        ;;
    bkiam)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/bkiam.env ]]; then
            source "$SELF_DIR"/04-final/bkiam.env
        fi
        if [[ -z "$BK_IAM_MYSQL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_IAM_MYSQL_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_IAM_MYSQL_PASSWORD" ]]; then
            gen_redis_password "BK_IAM" "$(rndpw 12)"
        fi
        if [[ -z "$BK_IAM_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_IAM_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        ;;
    bkiam_search_engine)
        set -a
        if [[ -r "$SELF_DIR"/04-final/bkiam_search_engine.env ]]; then
            source "$SELF_DIR"/04-final/bkiam_search_engine.env
        fi
        if [[ -z "$BK_IAM_SEARCH_ENGINE_ES7_PASSWORD" ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
            printf "%s=%q\n" "BK_IAM_SEARCH_ENGINE_ES7_PASSWORD" "$BK_ES7_ADMIN_PASSWORD"
        fi
        if [[ -z "$BK_IAM_SAAS_REDIS_PASSWORD" ]]; then
            gen_redis_password "BK_IAM_SAAS" "${redis_pwd}"
        fi
        ;;
    bknodeman)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/bknodeman.env ]]; then
            source "$SELF_DIR"/04-final/bknodeman.env
        fi
        str=$(gen_app_token_def bk_nodeman)
        eval "$str"
        [[ -n "$str" ]] && echo "$str"
        redis_pwd=$(rndpw 12)

        if [[ -z "$BK_NODEMAN_MYSQL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_NODEMAN_MYSQL_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_NODEMAN_RABBITMQ_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_NODEMAN_RABBITMQ_PASSWORD" "$(rndpw 12)"
        fi         
        if [[ -z "$BK_NODEMAN_REDIS_PASSWORD" ]]; then
            gen_redis_password "BK_NODEMAN" "${redis_pwd}"
        fi
        if [[ -z "$BK_NODEMAN_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_NODEMAN_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi

        ;;
    bkmonitorv3)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/bkmonitorv3.env ]]; then
            source "$SELF_DIR"/04-final/bkmonitorv3.env
        fi
        redis_pwd=$(rndpw 12)

        if [[ -z "$BK_MONITOR_APP_CODE" || -z "$BK_MONITOR_APP_SECRET" ]]; then
            printf "%s=%q\n" "BK_MONITOR_APP_CODE" "bk_bkmonitorv3"
            printf "%s=%q\n" "BK_MONITOR_APP_SECRET" "$(rndpw 12)"
        fi
        if [[ -z "$BK_MONITOR_MYSQL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_MONITOR_MYSQL_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_MONITOR_RABBITMQ_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_MONITOR_RABBITMQ_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_MONITOR_ES7_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_MONITOR_ES7_PASSWORD" "$BK_ES7_ADMIN_PASSWORD"
        fi
        if [[ -z "$BK_MONITOR_REDIS_PASSWORD" ]]; then
            gen_redis_password "BK_MONITOR" "${redis_pwd}"
        fi
        if [[ -z "$BK_MONITOR_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_MONITOR_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        if [[ -z $BK_MONITOR_INFLUXDB_USER ]];then
            printf "%s=%q\n" "BK_MONITOR_INFLUXDB_USER" "$BK_INFLUXDB_ADMIN_USER"
        fi
        if [[ -z $BK_MONITOR_INFLUXDB_PASSWORD ]];then
            printf "%s=%q\n" "BK_MONITOR_INFLUXDB_PASSWORD" "$BK_INFLUXDB_ADMIN_PASSWORD"
        fi
        if [[ -z "$BK_MONITOR_TRANSFER_REDIS_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_MONITOR_TRANSFER_REDIS_PASSWORD" "$BK_REDIS_ADMIN_PASSWORD"
        fi
        if [[ -z "$BK_MONITOR_TRANSFER_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_MONITOR_TRANSFER_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        ;;
    bklog)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/bklog.env ]]; then
            source "$SELF_DIR"/04-final/bklog.env
        fi
        str=$(gen_app_token_def bk_bklog)
        eval "$str"
        [[ -n "$str" ]] && echo "$str"
        if [[ -z "$BK_BKLOG_MYSQL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_BKLOG_MYSQL_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_BKLOG_REDIS_PASSWORD" ]]; then
            gen_redis_password "BK_BKLOG" "${redis_pwd}"
        fi
        if [[ -z "$BK_BKLOG_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_BKLOG_REDIS_SENTINEL_PASSWORD" "$BK_REDIS_SENTINEL_PASSWORD"
        fi
        ;;
    lesscode)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/lesscode.env ]]; then
            source "$SELF_DIR"/04-final/lesscode.env
        fi
        if [[ -z "$BK_LESSCODE_MYSQL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_LESSCODE_MYSQL_PASSWORD" "$(rndpw 12)"
        fi
        if [[ -z "$BK_LESSCODE_APP_SECRET" ]]; then
            printf "%s=%q\n" "BK_LESSCODE_APP_SECRET" "$(rndpw 51)"
        fi
        ;;
    dbadmin)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -z "$BK_CONSUL_KEYSTR_32BYTES" ]]; then
            printf "%s=%q\n" BK_CONSUL_KEYSTR_32BYTES "$(rndpw 32 | base64)"
        fi
        if [[ -z "$BK_MONGODB_KEYSTR_32BYTES" ]]; then
            printf "%s=%q\n" BK_MONGODB_KEYSTR_32BYTES "$(rndpw 32 | base64)"
        fi
        if [[ -z "$BK_MONGODB_ADMIN_USER" ]]; then
            printf "%s=%q\n" BK_MONGODB_ADMIN_USER root
        fi
        if [[ -z "$BK_MONGODB_ADMIN_PASSWORD" ]]; then
            printf "%s=%q\n" BK_MONGODB_ADMIN_PASSWORD "$(rndpw 12)"
        fi
        if [[ -z "$BK_MYSQL_ADMIN_USER" ]]; then
            printf "%s=%q\n" BK_MYSQL_ADMIN_USER root
        fi
        if [[ -z "$BK_MYSQL_ADMIN_PASSWORD" ]]; then
            printf "%s=%q\n" BK_MYSQL_ADMIN_PASSWORD "$(rndpw 12)"
        fi
        if [[ -z "$BK_RABBITMQ_ERLANG_COOKIES" ]]; then
            printf "%s=%q\n" BK_RABBITMQ_ERLANG_COOKIES "$(rndpw 10 | base64)"
        fi
        if [[ -z "$BK_RABBITMQ_ADMIN_PASSWORD" ]]; then
            printf "%s=%q\n" BK_RABBITMQ_ADMIN_PASSWORD "$(rndpw 12)"
        fi
        if [[ -z "$BK_RABBITMQ_ADMIN_USER" ]]; then
            printf "%s=%q\n" BK_RABBITMQ_ADMIN_USER admin
        fi
        if [[ -z "$BK_RABBITMQ_ADMIN_PASSWORD" ]]; then
            printf "%s=%q\n" BK_RABBITMQ_ADMIN_PASSWORD "$(rndpw 12)"
        fi
        # # redis sentinel共用，所以密码统一生成一次即可。
        if [[ -z "$BK_REDIS_SENTINEL_PASSWORD" ]]; then
            printf "%s=%q\n" BK_REDIS_SENTINEL_PASSWORD "$(rndpw 12)"
        fi
        if [[ -z "$BK_REDIS_ADMIN_PASSWORD" ]]; then
            printf "%s=%q\n" BK_REDIS_ADMIN_PASSWORD "$(rndpw 12)"
        fi
        # elastiscearch7的elastic账户的密码
        if [[ -z "$BK_ES7_ADMIN_PASSWORD" ]]; then
            printf "%s=%q\n" BK_ES7_ADMIN_PASSWORD "$(rndpw 12)"
        fi
        # influxdb的admin账户的密码
        if [[ -z "$BK_INFLUXDB_ADMIN_PASSWORD" ]]; then
            printf "%s=%q\n" BK_INFLUXDB_ADMIN_USER admin
            printf "%s=%q\n" BK_INFLUXDB_ADMIN_PASSWORD "$(rndpw 12)"
        fi
        ;;
    fta)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/fta.env ]]; then
            source "$SELF_DIR"/04-final/fta.env
        fi
        if [[ -z "$BK_FTA_MYSQL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_FTA_MYSQL_PASSWORD"  "$(rndpw 12)"
        fi
        if [[ -z "$BK_FTA_REDIS_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_FTA_REDIS_PASSWORD" "$BK_REDIS_ADMIN_PASSWORD"
        fi
        if [[ -z "$BK_FTA_APP_SECRET" ]]; then
            printf "%s=%q\n" "BK_FTA_APP_SECRET" "$(rndpw 12)"
        fi
        ;;
    bkapigw)
        if [[ -r "$SELF_DIR"/01-generate/dbadmin.env ]]; then
            source "$SELF_DIR"/01-generate/dbadmin.env
        fi
        if [[ -r "$SELF_DIR"/04-final/bkapigw.env ]]; then
            source "$SELF_DIR"/04-final/bkapigw.env
        fi
        source "$SELF_DIR/04-final/global.env"
        if [[ -z "$BK_APIGW_ENCRYPT_KEY" ]]; then
            printf "%s=%q\n" "BK_APIGW_ENCRYPT_KEY"  "$(rndpw 32 | base64)"
        fi
        if [[ -z "$BK_APIGW_APP_SECRET" ]]; then
            printf "%s=%q\n" "BK_APIGW_APP_SECRET" "$(uuid -v4)"

        fi
        if [[ -z "$BK_APIGW_TEST_APP_SECRET" ]]; then
            printf "%s=%q\n" "BK_APIGW_TEST_APP_SECRET" "$(uuid -v4)" 
        fi
        if [[ -z "$BK_APIGW_MYSQL_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_APIGW_MYSQL_PASSWORD"  "$(rndpw 16)"
        fi
        if [[ -z "$BK_APIGW_REDIS_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_APIGW_REDIS_PASSWORD"  "$BK_REDIS_ADMIN_PASSWORD"
        fi
        if [[ -z "$BK_APIGW_ES_PASSWORD" ]]; then
            printf "%s=%q\n" "BK_APIGW_ES_PASSWORD" "$BK_ES7_ADMIN_PASSWORD"
        fi
        if [[ -z "$BK_APIGW_APISIX_ADMIN_KEY" ]]; then
            printf "%s=%q\n" "BK_APIGW_APISIX_ADMIN_KEY" "$(rndpw 32)"
        fi
        ;;
    *)
        echo "Usage: $0 <dbadmin|模块名>" >&2
        exit 1
        ;;
esac
