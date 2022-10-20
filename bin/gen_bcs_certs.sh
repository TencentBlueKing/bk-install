#!/usr/bin/env bash

anynowtime="date +'%Y-%m-%d %H:%M:%S'"
NOW="echo [\`$anynowtime\`][PID:$$]"

##### 可在脚本开始运行时调用，打印当时的时间戳及PID。
function job_start
{
    echo "`eval $NOW` job_start"
}

##### 可在脚本执行成功的逻辑分支处调用，打印当时的时间戳及PID。 
function job_success
{
    MSG="$*"
    echo "`eval $NOW` job_success:[$MSG]"
    exit 0
}

##### 可在脚本执行失败的逻辑分支处调用，打印当时的时间戳及PID。
function job_fail
{
    MSG="$*"
    echo "`eval $NOW` job_fail:[$MSG]"
    exit 1
}

job_start

###### 可在此处开始编写您的脚本逻辑代码
###### 作业平台中执行脚本成功和失败的标准只取决于脚本最后一条执行语句的返回值
###### 如果返回值为0，则认为此脚本执行成功，如果非0，则认为脚本执行失败
BCS_HOME='/root'
BCS_CERT_PATH=${BCS_CERT_PATH:-/etc/ssl/bcs}
SSL_CONF_DIR=$BCS_HOME/.cfssl/
install -dv "$BCS_HOME/.cfssl"

# 生成bcs-ca-csr.json文件
cat <<EOF > "$BCS_HOME"/.cfssl/bcs-ca-csr.json
{
    "CN": "BCS own CA",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "SZ",
            "O": "TX",
            "ST": "GD",
            "OU": "CA"
        }
    ]
}
EOF

# 生成文件bcs-ca-config.json
cat <<EOF > "$BCS_HOME"/.cfssl/bcs-ca-config.json
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "peers": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF

# 生成证书函数
gen_bcs_cert () {
    local bcs_ca_cert=$BCS_CERT_PATH/bcs-ca.pem
    local role=$1

    install -dv "${bcs_ca_cert%/*}"

    # gen CA
    if [[ ! -f ${bcs_ca_cert} ]]; then
        cfssl gencert -initca "$SSL_CONF_DIR/bcs-ca-csr.json" \
            | cfssljson -bare "${bcs_ca_cert%.pem}" -
    fi

    # gen bcs-csr.json
    if [[ $role == 'bcs-api' ]]; then
        cat > "$SSL_CONF_DIR/bcs-api.json" << EOF
{
    "CN": "bktencent.com",
    "hosts": [
        "bktencent.com",
        "127.0.0.1"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "SZ",
            "O": "TX",
            "ST": "GD",
            "OU": "BK"
        }
    ]
}
EOF
        # gen bcs cert
        if [[ ! -f ${bcs_ca_cert%/*}/bcs-api.pem ]]; then
            cfssl gencert -ca="${bcs_ca_cert}" \
                -ca-key="${bcs_ca_cert%/*}/bcs-ca-key.pem" \
                -config="$SSL_CONF_DIR/bcs-ca-config.json" \
                -profile=peers \
                "$SSL_CONF_DIR/bcs-api.json" \
                | cfssljson -bare "${bcs_ca_cert%/*}/bcs-api"
        fi
    else
        # gen client flanneld cert
        if [[ ! -f ${bcs_ca_cert%/*}/${role}.pem ]]; then
		cat > "$BCS_HOME/.cfssl/${role}.json" <<EOF
{
    "CN": "${role}",
    "hosts": [""],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "SZ",
            "O": "TX",
            "ST": "GD",
            "OU": "BK"
        }
    ]
}
EOF
             
            cfssl gencert -ca="${bcs_ca_cert}" \
                -ca-key="${bcs_ca_cert%/*}/bcs-ca-key.pem" \
                -config="$SSL_CONF_DIR/bcs-ca-config.json" \
                -profile=client \
                "$SSL_CONF_DIR/${role}.json" \
                | cfssljson -bare "${bcs_ca_cert%/*}/${role}"
        fi
    fi
}

gen_bcs_cert bcs-api
gen_bcs_cert bcs-client	# 生成bcs模块访问bcs的证书
gen_bcs_cert bcs-server	# 生成bcs模块访问bcs的证书
rm -f /etc/ssl/bcs/*.csr
job_success "bcs cert create success"
