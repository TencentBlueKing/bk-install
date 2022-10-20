#!/usr/bin/env bash

ETCD_CERT_PATH=${ETCD_CERT_PATH:-/etc/ssl/etcd}
SSL_CONF_DIR=$HOME/.cfssl/

ETCD_IPS=( $@ )

install -dv "$HOME/.cfssl"

cat <<EOF > $HOME/.cfssl/etcd-ca-csr.json
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

cat <<EOF > $HOME/.cfssl/etcd-ca-config.json
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


gen_etcd_cert () {
    local etcd_ca_cert=$ETCD_CERT_PATH/etcd-ca.pem
    local role=$1 i

    install -dv "${etcd_ca_cert%/*}"

    # gen CA
    if [[ ! -f ${etcd_ca_cert} ]]; then
        cfssl gencert -initca "$SSL_CONF_DIR/etcd-ca-csr.json" \
            | cfssljson -bare "${etcd_ca_cert%.pem}" -
    fi

    # gen etcd-csr.json
    if [[ $role == 'etcd' ]]; then
        for ((i=0; i<${#ETCD_IPS[@]}; i++)); do
            cat > "$SSL_CONF_DIR/etcd${i}.json" << EOF
{
    "CN": "etcd${i}",
    "hosts": [
        "${ETCD_IPS[$i]}",
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
            "ST": "GD"
        }
    ]
}
EOF
            # gen etcd cert
            if [[ ! -f ${etcd_ca_cert%/*}/etcd${i}.pem ]]; then
                cfssl gencert -ca="${etcd_ca_cert}" \
                    -ca-key="${etcd_ca_cert%/*}/etcd-ca-key.pem" \
                    -config="$SSL_CONF_DIR/etcd-ca-config.json" \
                    -profile=peers \
                    "$SSL_CONF_DIR/etcd${i}.json" \
                    | cfssljson -bare "${etcd_ca_cert%/*}/etcd${i}"
            fi
        done
    else
        # gen client flanneld cert
        if [[ ! -f ${etcd_ca_cert%/*}/${role}.pem ]]; then
		cat > "$HOME/.cfssl/${role}.json" <<EOF
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
            "ST": "GD"
        }
    ]
}
EOF
             
            cfssl gencert -ca="${etcd_ca_cert}" \
                -ca-key="${etcd_ca_cert%/*}/etcd-ca-key.pem" \
                -config="$SSL_CONF_DIR/etcd-ca-config.json" \
                -profile=client \
                "$SSL_CONF_DIR/${role}.json" \
                | cfssljson -bare "${etcd_ca_cert%/*}/${role}"
        fi
    fi
}

gen_etcd_cert etcd
gen_etcd_cert bcs-etcd	# 生成bcs模块访问etcd的证书
