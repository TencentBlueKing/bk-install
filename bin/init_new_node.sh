#!/usr/bin/env bash
# Description: 新增蓝鲸主机时，做基础的初始化，它主要是封装其他脚本，应该在新节点上执行

set -euo pipefail

SELF_DIR=$(readlink -f $(dirname "$0"))
if ! [[ -f ${SELF_DIR}/../.controller_ip ]]; then
    echo "please make sure your have sync $(dirname "$SELF_DIR")/.controller_ip to this host."
    exit 1
fi

echo "generate $HOME/.bkrc. modify $HOME/.bashrc to include $HOME/.bkrc"
source ${SELF_DIR}/../functions # get gen_bkrc ()
source ${SELF_DIR}/../.rcmdrc   # get CTRL_DIR CTRL_IP
source ${CTRL_DIR}/load_env.sh  # get all other ENV
gen_bkrc

echo "create essential directory"
[[ -d ${BK_PKG_SRC_PATH} ]] || mkdir -p "${BK_PKG_SRC_PATH}/backup"
for DIR in cert etc public logs; do 
    if [[ ! -d ${BK_HOME}/$DIR ]]; then 
        mkdir -p "${BK_HOME}/$DIR"
    fi
done

echo "initialising blueking environment"
BK_BLUEKING_UID=$BK_BLUEKING_UID BK_BLUEKING_GID=$BK_BLUEKING_GID "$CTRL_DIR"/bin/update_bk_env.sh

# 新增yum源（如果存在）否则报错
if ! yum info consul; then
    echo "there is no valid consul package in yum repo. please check /etc/yum.repos.d/Blueking.repo"
    exit 2
fi

# 安装consul client
if [[ -f /etc/blueking/env/local.env ]]; then
    source /etc/blueking/env/local.env
    if [[ -z $LAN_IP ]]; then
        echo "get LAN_IP from /etc/blueking/env/local.env failed"
        exit 1
    fi
else
    echo "no /etc/blueking/env/local.env found"
    exit 1
fi

"$CTRL_DIR"/bin/install_consul.sh -e "$BK_CONSUL_KEYSTR_32BYTES" -j "$BK_CONSUL_IP_COMMA" -r client --dns-port 53 -b "$LAN_IP"