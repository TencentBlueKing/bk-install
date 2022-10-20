#!/usr/bin/env bash
# install_vault.sh: Vault deployment script. Vault is a tool for securely accessing secrets.
# 参考文档: https://learn.hashicorp.com/vault/day-one/ops-vault-ha-consul
# 备注: Vault autounseal方案不适用于企业版通用部署方案，所以在Vault进程每次重启之后都需要执行unseal操作
# 用法：
#   - 安装：  bash /data/install/bin/install_vault.sh -b $LAN_IP -i -u -e
#   - unseal：  bash /data/install/bin/install_vault.sh -b $LAN_IP -u

# 安全模式
set -euo pipefail 

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
BIND_ADDR="127.0.0.1"
PORT="8200"
CLUSTER_PORT='8201'
PREFIX="/data/bkee"
TOKEN_FILE='/etc/vault/vault.token'
CLUSTER_ADDR='127.0.0.1'
CONSUL_ADDR='127.0.0.1'
CONSUL_PORT="8500"
INSTALL_ACTION=0
UNSEAL_VAULT=0
ENABLE_SECRET=0

# Vault管理变量
ENV='ee'
KV_ENGINE_PATH='bk-secrets-kv'
TRANSIT_ENGINE_PATH='bk-secrets-transit'
VAULT_PATH='/etc/vault/vault'

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -b --bind-addr           [可选] Vault监听网卡地址,默认为'127.0.0.1']
            [ -p --port                [可选] Vault监听端口，默认为'8200']
            [ -P --consul-port         [可选] 后端存储Consul监听端口,默认为'8500']
            [ -s --cluster-addr        [可选] 绑定到集群服务器到服务器请求的地址,默认为'127.0.0.1']
            [ -S --cluster-port        [可选] 绑定到集群服务器到服务器请求的端口,默认为'8201']
            [ -c --consul-addr         [可选] 后端存储Consul地址，默认为'127.0.0.1']
            [ -t --token-file          [可选] Vault Token本地存储文件,默认为/etc/vault/vault.token]
            [ -k --kv-engine-path      [可选] Vault key/value 引擎PATH，默认为bk-secrets-kv]
            [ -T --transit-engine-path [可选] Vault 加密服务PATH，处理传输数据,不存储数据,默认为bk-secrets-transit]
            [ -i --install-action      [可选] 是否执行安装动作,默认为否]
            [ -u --unseal-vault        [可选] 是否执行unseal，默认为否]
            [ -e --enable-secrets      [可选] 是否启用密钥引擎,默认为否]
            [ --prefix                 [可选] 安装的目标路径，默认为/data/bkee ]
            [ -v, --version            [可选] 查看脚本版本号 ]
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
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -p | --port )
            shift
            PORT=$1
            ;;
        -P | --consul-port )
            shift
            CONSUL_PORT=$1
            ;;
        -s | --cluster-addr )
            shift
            CLUSTER_ADDR=$1
            ;;
        -S | --cluster-port )
            shift
            CLUSTER_PORT=$1
            ;;
        -c | --consul-addr)
            shift
            CONSUL_ADDR=$1
            ;;
        --prefix)
            shift
            PREFIX=$1
            ;;
        -t | --token-file )
            shift
            TOKEN_FILE=$1
            ;;
        -T | --transit-engine-path)
            shift
            TRANSIT_ENGINE_PATH=$1
            ;;
        -k | --kv-engine-path)
            shift
            KV_ENGINE_PATH=$1
            ;;
        -i | --install-action )
            INSTALL_ACTION=1 
            ;;
        -u | --unseal-vault)
            UNSEAL_VAULT=1
            ;;
        -e | --enable-secrets )
            ENABLE_SECRET=1
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
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# -i: 安装vault并初始化
if [[ ${INSTALL_ACTION} == 1 ]];then
    # 安装vault,后期使用yum安装，目前先特殊处理
    if ! [[ -d /etc/vault ]];then
        install -o blueking -g blueking -d /etc/vault && log "创建/etc/vault目录"
    fi

    if ! [[ -f /data/src/service/vault ]];then
        warning "vault do not exist"
    fi

    rsync -avz /data/src/service/vault /etc/vault/  && log "同步vault二进制到/etc/vault"

    #安装用户和配置目录
    LOG_DIR=${LOG_DIR:-$PREFIX/logs/vault}

    id -u blueking &>/dev/null || \
        { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; } 

    install -o blueking -g blueking -d "${LOG_DIR}"
    install -o blueking -g blueking -m 755 -d /etc/blueking/env 
    install -o blueking -g blueking -m 755 -d "/etc/vault/"
    install -o blueking -g blueking -m 755 -d /var/run/vault


    # 创建配置文件，集群启动配置文件不与鉴权配置文件共用
    cat > /etc/vault/vault.hcl <<EOF
listener "tcp" {
  address       = "${BIND_ADDR}:${PORT}"
  cluster_address = "${CONSUL_ADDR}:${CLUSTER_PORT}"
  tls_disable = 1
}

storage "consul" {
  address = "${CONSUL_ADDR}:${CONSUL_PORT}"
  path = "vault/"
}
# 通告给群集中其他Vault服务器以进行客户端重定向的地址
api_addr = "http://${BIND_ADDR}:${PORT}"
cluster_addr = "https://${CLUSTER_ADDR}:${CLUSTER_PORT}"
EOF
    # 创建systemed配置文件
    cat <<EOF > /etc/systemd/system/vault.service
[Unit]
Description=Vault secret management tool
Requires=network-online.target
After=network-online.target

[Service]
User=blueking
Group=blueking
PIDFile=/var/run/vault/vault.pid
ExecStart=/etc/vault/vault server -config=/etc/vault/vault.hcl -log-level=debug
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
RestartSec=42s
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF
    # 启动vault，不成功则不进行初始化操作
    systemctl daemon-reload
    systemctl start vault
    if ! systemctl status vault.service ;then
        log "请检查启动日志，使用命令：journalctl -u Vault 查看失败原因"
        log "手动修复后，使用命令：systemctl start Vault 启动并确认是否启动成功"
        log "启动成功后，使用命令：systemctl enable Vault 设置开机启动"
        usage_and_exit "Vault 安装失败"
    else
        log "设置 Vault 开机启动"
        systemctl enable vault.service
    fi

    if ! [[ $(curl -s --connect-timeout 2 http://"${BIND_ADDR}:${PORT}"/v1/sys/health |jq '.initialized') == 'true' ]] ; then
        # Init Vault并把root Token，unseal Token重定向到TOKEN_FILE
        tmpfile=$(mktemp /tmp/vault.XXXXXXXXX)
        # 使用api接口方式init更合适 待测试
        export VAULT_ADDR=http://${BIND_ADDR}:${PORT}
        "${VAULT_PATH}" operator init -key-shares=3  > "${tmpfile}" || error "Init Vault failed!"
        VAULT_UNSEAL_KEY=(
                $(awk -F ': '  '/Unseal Key 1/{print $2}' "${tmpfile}") \
                $(awk -F ': '  '/Unseal Key 2/{print $2}' "${tmpfile}") \
                $(awk -F ': '  '/Unseal Key 3/{print $2}' "${tmpfile}") \
        )
        VAULT_ROOT_TOKEN=$(awk -F ': ' '/Initial Root Token/{print $2}' "${tmpfile}")
        # 创建TOKEN FILE,并设置为只读权限
        cat > "${TOKEN_FILE}" <<EOF
export VAULT_UNSEAL_KEY=(${VAULT_UNSEAL_KEY[@]})
export VAULT_ROOT_TOKEN=${VAULT_ROOT_TOKEN}
EOF
        chattr +i "${TOKEN_FILE}"
    fi
    log "Successful startup and initialization vault and save the token in the ${TOKEN_FILE}!"

fi

# -u：Unseal vault after init.
if [[ "${UNSEAL_VAULT}" == 1 ]];then
    # 检查Vault是否初始化
    if ! curl -s --connect-timeout 2 http://"${BIND_ADDR}:${PORT}"/v1/sys/health >/dev/null ; then
        error "Connection timed out after 2001 milliseconds, please check!"
    fi
    result=$(curl -s --connect-timeout 2 http://"${BIND_ADDR}:${PORT}"/v1/sys/health)
    if ! [[ $(jq '.initialized' <<< "$result" ) == 'true' ]];then
        error "Vault  has not been initialized!"
    fi
    # 检查Vault是否已经unseal
    if  [[ $(jq '.sealed' <<< "$result" ) == 'false' ]];then
        log "Vault has been unsealed!"
        exit 0
    fi
    # 检查TOKEN_FILE
    if ! [[ -f "${TOKEN_FILE}" ]];then
        error "${TOKEN_FILE} not exist,please check!"
    else
        source "${TOKEN_FILE}"
    fi
    # Unseal vault by API
    for key in "${!VAULT_UNSEAL_KEY[@]}";do
        json=$(cat <<EOF
{
    "key" : "${VAULT_UNSEAL_KEY[${key}]}"
}
EOF
)
        unseal_result=$(curl -s -X PUT --data "${json}" http://"${BIND_ADDR}:${PORT}"/v1/sys/unseal |jq .sealed)
    done
    if ! [[ "${unseal_result}" == "false" ]]; then
        error "Unseal vault filed"
    fi
    log "Unsealed vault!"
fi

# -e: 启用kv、transit引擎,签发bk-secrets-token、bk-env-token
# 权限管理粒度变量
if [[ "${ENABLE_SECRET}" == 1 ]];then
    # 检查Vault是否初始化
    if ! curl -s --connect-timeout 2 http://"${BIND_ADDR}:${PORT}"/v1/sys/health >/dev/null ; then
        error "Connection timed out after 2001 milliseconds, please check!"
    fi
    result=$(curl -s --connect-timeout 2 http://"${BIND_ADDR}:${PORT}"/v1/sys/health)
    if ! [[ $(jq '.initialized' <<< "$result" ) == 'true' ]];then
        error "Vault has not been initialized!"
    fi
    # 检查Vault是否已经unseal
    if ! [[ $(jq '.sealed' <<< "$result" ) == 'false' ]];then
        error "Vault has not been unsealed!"
    fi
    # 检查TOKEN_FILE
    if ! [[ -f "${TOKEN_FILE}" ]];then
        error "${TOKEN_FILE} not exist,please check!"
    else
        source "${TOKEN_FILE}"
    fi

    # Enable kv、transit engine 
    kv_json=$(cat <<EOF
{
  "type": "kv",
  "options": {
    "version": "2"
  },
  "config": {
    "force_no_cache": true
  }
}
EOF
)
    transit_json=$(cat <<EOF
{"type":"transit"}
EOF
)
    if curl -s -X POST  \
                --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
                --data "${kv_json}" \
                http://"${BIND_ADDR}:${PORT}""/v1/sys/mounts/""${KV_ENGINE_PATH}";then
        log "Enabel kv engine successfully!"
    fi
    if curl -s -X POST  \
                --header "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
                --data "${transit_json}" \
                http://"${BIND_ADDR}:${PORT}""/v1/sys/mounts/""${TRANSIT_ENGINE_PATH}";then
        log "Enabel transit engine successfully!"
    fi

fi

