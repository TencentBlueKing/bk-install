#!/usr/bin/env bash

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

source "$HOME/.bashrc"
source "$CTRL_DIR/utils.fc"

PRETTY=0

declare -ra open_src_modules=( 
    consul java mysql mongodb
    redis influxdb es zk kafka rabbitmq nginx beanstalk
)

declare -ra bk_backend=(
    iam usermgr paas paas_agent paas_plugins cmdb gse license job
    service
    bkmonitor bkmonitorv3 bklog bknodeman fta
)
declare -ra bk_saas=( 
    bk_nodeman
    bk_sops
    bk_monitor
    bk_log_search
    bk_fta_solutions
    bk_iam_app
    bk_user_manage
    bk_bcs_app
    bk_bcs_monitor
    bk_dataweb
)

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -o, --opensrc     [可选] 指定需要查看的开源组件名的版本号，逗号分隔，如果为ALL则查看所有的 ]
            [ -b, --backend     [可选] 指定需要查看的蓝鲸后台组件名的版本号，逗号分隔，如果为ALL则查看所有的 ]
            [ -s, --saas        [可选] 指定需要查看的蓝鲸SaaS的版本号，逗号分隔，如果为ALL则查看所有的 ]

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

get_bk_backend_version () {
    local module=$1

    case $module in
    paas) module=open_paas ;;
    esac

    if [ -f "$PKG_SRC_PATH/$module/VERSION" ]; then
        printf "%s %s\n" "$module" "$(< "$PKG_SRC_PATH"/$module/VERSION)"
        return 0
    else
        echo "$module NULL"
    fi
}
    
get_bk_saas_version () {
    local saas=$1
    local app_id app_cur_version
    app_id=$(MYSQL_PWD="$MYSQL_PASS" mysql -u"$MYSQL_USER" -h "$MYSQL_IP0" -NBe "use open_paas; select id from paas_saas_app where code = \"$saas\";")
    if [[ -z $app_id ]]; then
        app_cur_version="NULL"
    else
        app_cur_version=$(MYSQL_PWD=$MYSQL_PASS mysql -u$MYSQL_USER -h $MYSQL_IP0 -NBe \
        "use open_paas; select  id,version,saas_app_id from  paas_saas_app_version where saas_app_id = $app_id" \
        | tail -1 | awk '{print $2}')
        [[ -z $app_cur_version ]] && app_cur_version="NULL"
    fi
    printf "%s %s\n" "$saas" "$app_cur_version"
}

get_opensrc_version () {
    case $1 in
    consul) 
        echo "==Consul=="
        consul version
         ;;
    java)
        echo "==Java=="
        $PKG_SRC_PATH/service/java/bin/java -version
        ;;

    mysql)
        echo "==MySQL=="
        $PKG_SRC_PATH/service/mysql/bin/mysqld --version
        ;;
    mongodb)
        echo "==MongoDB=="
        $PKG_SRC_PATH/service/mongodb/bin/mongod --version
        ;;
    redis)
        echo "==Redis=="
        $PKG_SRC_PATH/service/redis/bin/redis-server --version
        ;;
    influxdb)
        echo "==InluxDB=="
        ssh $INFLUXDB_IP influx --version
        ;;
    zk|zookeeper)
        echo "==Zookeeper=="
        { echo -e "envi\r"; sleep 1; }   | telnet $ZK_IP 2181 2>/dev/null | grep zookeeper.version
        ;;
    kafka)
        echo "==Kafka=="
        echo "kafka: " $(cd $PKG_SRC_PATH/service/kafka/ && find libs/ -name "*kafka_*.jar" | head -1 | cut -d- -f2)
        ;;
    rabbitmq|mq)
        echo "==RabbitMQ=="
        ssh $RABBITMQ_IP "rabbitmqctl status | grep rabbit,"
        ;;
    nginx)
        echo "==Nginx=="
        ssh $NGINX_IP nginx -v
        ;;
    beanstalk)
        echo "==Beanstalk=="
        ssh $BEANSTALK_IP beanstalkd -v
        ;;
        es|elasticsearch)
        echo "==Elasticsearch=="
        curl -s $ES_HOST:$ES_REST_PORT
        ;;
    confd)
        echo "==confd=="
        echo "confd: $($PKG_SRC_PATH/service/confd/bin/confd --version)"
        ;;
    etcd)
        echo "==etcd=="
        echo "etcd: $($PKG_SRC_PATH/service/etcd/etcd --version | head -1)"
        ;;

    *)
        echo "unknown"
        exit 1
        ;;
    esac
    echo 
}

get_gse_plugin_version () {
    local plugin_name=$1
    curl -s http://paas.service.consul/o/bk_nodeman/api/${plugin_name}/package/?os=LINUX | jq 
}
# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -o | --opensrc )
            shift
            OPENSRC_TARGET="$1"
            ;;
        -b | --backend)
            shift
            BACKEND_TARGET="$1"
            ;;
        -s | --saas)
            shift
            SAAS_TARGET="$1"
            ;;
        -p | --pretty)
            shift
            PRETTY=1
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

{ 
if [[ -n $OPENSRC_TARGET ]]; then
    if [[ $OPENSRC_TARGET = "ALL" ]]; then
        foo=( "${open_src_modules[@]}" )
    else
        IFS="," read -r -a foo <<<"$OPENSRC_TARGET"
    fi
    for m in "${foo[@]}"; do
        get_opensrc_version "$m"
    done
fi
if [[ -n $BACKEND_TARGET ]]; then
    if [[ $BACKEND_TARGET = "ALL" ]]; then
        foo=( "${bk_backend[@]}" )
    else
        IFS="," read -r -a foo <<<"$BACKEND_TARGET"
    fi
    for m in "${foo[@]}"; do
        get_bk_backend_version "$m"
    done
fi
if [[ -n $SAAS_TARGET ]]; then
    if [[ $SAAS_TARGET = "ALL" ]]; then
        foo=( "${bk_saas[@]}" )
    else
        IFS="," read -r -a foo <<<"$BACKEND_TARGET"
    fi
    for m in "${foo[@]}"; do
        get_bk_saas_version "$m"
    done
fi
} | column -t 