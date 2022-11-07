#!/usr/bin/env bash
# 用途：安装和更新蓝鲸的license_server，证书服务
# 
# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局参数
BIND_ADDRESS=127.0.0.1

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]

            [ -b, --bind        [必填] "监听的网卡地址，默认127.0.0.1" ]
            [ -e, --envfile     [必填] "以该环境变量文件渲染配置" ]
            [ -s, --srcdir      [必填] "从该目录拷贝license/目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ -c, --cert-path   [可选] "企业版证书存放目录，默认为$PREFIX/cert" ]
            [ -l, --log-dir     [可选] "日志目录,默认为$PREFIX/logs/license" ]

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

check_license_svr () {
    local cert_path=$1
    local license_check_url=$2
    local cert_str platform timestamp json_msg res
    cert_str=$(awk 'BEGIN { ORS="\\n" } 1' "$cert_path")
    platform="open_paas"
    timestamp=$(date -u +"%F %T")

    printf -v json_msg '{ "certificate": "%s", "platform": "%s", "requesttime": "%s" }\n' \
        "$cert_str" "$platform" "$timestamp"
    
    res=$(curl -s -k -d "$json_msg" -H "Content-Type: application/json" -X POST "$license_check_url")
    if [[ $res =~ success ]]; then
        return 0
    else
        echo "$res"
        return 1
    fi
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -b | --bind )
            shift
            BIND_ADDRESS=$1
            ;;
        -e | --envfile )
            shift
            ENV_FILE=$1
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -l | --log-dir )
            shift
            LOG_DIR=$1
            ;; 
        -c | --cert-path)
            shift
            CERT_PATH=$1
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/license}
CERT_PATH=${BK_CERT_PATH:-$PREFIX/cert}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR" ]]; then
    warning "$MODULE_SRC_DIR 不存在"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "$ENV_FILE 不存在"
fi
if ! [[ -r $CERT_PATH/license_prv.key && -r $CERT_PATH/license_cert.cert ]]; then
    warning "证书文件 $CERT_PATH/{license_prv.key,license_cert.cert}不存在"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; } 

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env 

# 拷贝模块目录到$PREFIX
rsync -a "$MODULE_SRC_DIR/license" "$PREFIX/" || error "安装模块(license)失败"

# 渲染配置
"$SELF_DIR"/render_tpl -e "$ENV_FILE" -E LAN_IP="$BIND_ADDRESS" -m license -p "$PREFIX" "$PREFIX"/license/support-files/templates/*

chown -R blueking.blueking "$PREFIX/license"


# 生成service文件
cat > /usr/lib/systemd/system/bk-license.service <<EOF
[Unit]
Description="Blueking License Server"
After=network-online.target
PartOf=blueking.target
ConditionFileNotEmpty=$CERT_PATH/license_cert.cert

[Service]
User=blueking
Group=blueking
ExecStart=$PREFIX/license/license/bin/license_server -config $PREFIX/etc/license.json
KillMode=process
Restart=on-failure
RestartSec=3s
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target blueking.target
EOF

systemctl daemon-reload
if ! systemctl is-enabled "bk-license" &>/dev/null; then
    systemctl enable --now bk-license
else
    systemctl start bk-license
fi

# 校验是否成功
systemctl status bk-license

check_license_svr "$CERT_PATH"/platform.cert https://$BIND_ADDRESS:8443/certificate