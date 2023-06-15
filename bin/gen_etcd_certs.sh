#!/usr/bin/env bash

ETCD_CERT_PATH=${ETCD_CERT_PATH:-/etc/ssl/etcd}
SSL_CONF_DIR=$HOME/.cfssl/

ETCD_IPS=


usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -p, --cert-path   etcd 证书的存放目录 ]
            [ -i, --ip     etcd 的 ip 列表]
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

fail () {
    echo "$@" 1>&2
    exit 1
}

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}


while (( $# > 0 )); do
    case "$1" in
        -p | --cert-path)
            shift
            ETCD_CERT_PATH=$1
            ;;
        -i | --ip)
            shift
            ETCD_IPS=( $1 )
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

if [[ -z ${ETCD_IPS[@]} ]];then
    error "etcd ip 列表不能为空"
fi

if ! [[ -d "$HOME/.cfssl" ]]; then 
    install -dv "$HOME/.cfssl"
fi

if ! [[ -d "${ETCD_CERT_PATH}" ]]; then
   install -dv "${ETCD_CERT_PATH}"
fi

if ! command -v cfssl &>/dev/null; then
    error "cfssl: command not found"
fi

if ! command -v cfssljson &>/dev/null; then
    error "cfssljson: command not found"
fi

cat <<EOF > "$HOME"/.cfssl/etcd-ca-csr.json
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

cat <<EOF > "$HOME"/.cfssl/etcd-ca-config.json
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
    local tmpfile

    tmpfile=$(mktemp /tmp/add_etcd_host.XXXXXXXXX)
    trap 'rm -f $tmpfile' EXIT

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
        "etcd.service.consul",
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
        convert_etcd_host="$(sed 's/ /","/g' <<< "${ETCD_IPS[@]}")"
        jq --arg convert_etcd_host "$convert_etcd_host" ".hosts |= .+ [\"$convert_etcd_host\"]" "$SSL_CONF_DIR/etcd${i}.json" > "$tmpfile"
        cp -a -f "$tmpfile" "$SSL_CONF_DIR/etcd${i}.json"

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
