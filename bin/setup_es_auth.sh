#!/usr/bin/env bash
# setup_es_auth.sh ：启动es官方X-pack插件，增加es访问鉴权
# 用法：./setup_es_auth.sh -s  -b $ES7_IP -P 9200 -p elasticsearch  修改elastic用户密码
# 用法: ./setup_es_auth.sh -g   生成鉴权文件
# 用法：./setup_es_auth.sh -a   启动xpack插件

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
NAME="elasticsearch"
PASSWORD='elastic'

PREFIX="/usr/share/elasticsearch"
ES_REST_PORT="9200"
BIND_ADDR="127.0.0.1"

GET_CERT_CONFIG=0
SET_PASSSWD=0
AUTH_CONFIG=0


usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?        [可选] "查看帮助" ]
            [ -P --es-rest-port    [可选] "指定ES_REST_PORT,默认为10004" ]
            [ -b --bind_addr       [可选] "指定监听地址，默认为127.0.0.1" ]
            [ -p --passwd          [可选] "指定elastic密码,默认为elastic" ]
            [ -a --auth-config     [可选] "指定为"1"确认修改本机ES配置,默认为"0"" ]
            [ -g --get-cert-config [可选] "指定为"1"确认生成cert文件,默认为"0"" ]
            [ -s --set-passwd      [可选] "指定为"1"确认初始化认证密码",默认为"0" ]
            [ -v, --version        [可选] "查看脚本版本号" ]
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
        -b  | --bind_addr )
            shift
            BIND_ADDR=$1
            ;;
        -P | --es-rest-port )
            shift
            ES_REST_PORT=$1
            ;;
        -p  | --password )
            shift
            PASSWORD=$1
            ;;
        -a | --auth-config )
            AUTH_CONFIG=1
            ;;
        -g  | --get-cert-config )
            GET_CERT_CONFIG=1
            ;;
        -s  | --set-passwd )
            SET_PASSSWD=1
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

# 参数合法性有效性校验，这些可以使用通用函数校验。

# 安装
if ! rpm -q elasticsearch &>/dev/null; then
    error "$NAME 未安装"
fi

# -g,则重新生成鉴权文件

if [  $GET_CERT_CONFIG  -eq 1 ];then
    if  ! [ -f /etc/elasticsearch/elastic-certificates.p12  ];then
        unset JAVA_HOME
        log "生成证书文件elastic-certificates.p12 "
        $PREFIX/bin/elasticsearch-certutil cert -out /etc/elasticsearch/elastic-certificates.p12 -pass "" > /dev/null 2>&1
        chown -R $NAME:$NAME /etc/elasticsearch//elastic-certificates.p12
    else
        log "删除原证书文件elastic-certificates.p12 "
        rm -f /etc/elasticsearch/elastic-certificates.p12
        unset JAVA_HOME
        log " 生成证书文件elastic-certificates.p12 "
        $PREFIX/bin/elasticsearch-certutil cert -out /etc/elasticsearch/elastic-certificates.p12 -pass ""   >/dev/null 2>&1
        if [ $? -eq 0 ];then
            chown -R $NAME:$NAME /etc/elasticsearch//elastic-certificates.p12
        else
            error "生成证书失败"
        fi
    fi

fi

# -a,则启动xpack插件,修改配置文件,并重启ES

if  [  $AUTH_CONFIG  -eq 1 ];then
    log "写入es配置,启动xpack插件"
    CONF_FILE=/etc/$NAME/${NAME}.yml
    sed -i '/^xpack/d' $CONF_FILE
    cat << EOF >> $CONF_FILE
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate 
xpack.security.transport.ssl.keystore.path: elastic-certificates.p12 
xpack.security.transport.ssl.truststore.path: elastic-certificates.p12 
EOF
    # 重启es
    log "重启es"
    systemctl restart elasticsearch.service >/dev/null 2>&1
    log "检查${NAME} 状态"
    if ! systemctl status "${NAME}" > /dev/null 2>&1; then
        log "请检查启动日志，使用命令：journalctl -u ${NAME} 查看失败原因"
        log "手动修复后，使用命令：systemctl start ${NAME} 启动并确认是否启动成功"
        log "启动成功后，使用命令：systemctl enable ${NAME} 设置开机启动"
        exit 100
    fi
fi

# -s ,则初始化es密码修改，并修改elastic用户密码
if  [ $SET_PASSSWD  -eq 1 -o -z "$BIND_ADDR" -o -z "$ES_REST_PORT" ];then
    log "检查es状态信息"
    if ! systemctl status "${NAME}" > /dev/null 2>&1 ; then
        log "请检查启动日志，使用命令：journalctl -u ${NAME} 查看失败原因"
        log "手动修复后，使用命令：systemctl start ${NAME} 启动并确认是否启动成功"
        log "启动成功后，使用命令：systemctl enable ${NAME} 设置开机启动"
        exit 100
    fi

    log "检查证书文件"
    if ! [[ -f /etc/elasticsearch/elastic-certificates.p12 ]];then
        error "certificates 文件不存在"
    fi

    temp_pass=$(mktemp /tmp/elasticsearch_XXXXXXX)
    unset JAVA_HOME
    $PREFIX/bin/elasticsearch-setup-passwords auto -b > "$temp_pass"
    auto_pass=$(awk '/PASSWORD elastic/{print $4}' "$temp_pass") 
    PASSWORD_API="http://$BIND_ADDR:$ES_REST_PORT/_xpack/security/user/elastic/_password"
    json=$(cat <<EOF
{ "password" : "$PASSWORD" }
EOF
)
    result=$(curl -s -X PUT -H 'Content-Type: application/json' "$PASSWORD_API" -u elastic:"$auto_pass" -d "$json")
    if [[ $(jq '.status' <<< ${result}) -eq 401 ]];then
        error "elastic 密码修改失败, 该集群已初始化默认用户角色"
    else    
        log "elastic 密码重置为: ${PASSWORD}"
    fi

fi