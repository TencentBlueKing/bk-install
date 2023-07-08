#!/usr/bin/env bash

set -euo pipefail

CTRL_DIR=${CTRL_DIR:-/data/install}
SSH_CONNECTION=${SSH_CONNECTION-}

# 
BK_UID=${BK_BLUEKING_UID:-10000}
BK_GID=${BK_BLUEKING_GID:-10000}

# create blueking user and group
getent group blueking &>/dev/null || \
    groupadd --gid "$BK_GID" blueking
id -u blueking &>/dev/null || \
    useradd --uid "$BK_UID" --gid "$BK_GID" -m -d /home/blueking -c "BlueKing EE User" --shell /bin/bash blueking 

install -o blueking -g blueking -m 755 -d /etc/blueking/env 

# create blueking target
if ! [[ -f /usr/lib/systemd/system/blueking.target ]]; then
    cat > /usr/lib/systemd/system/blueking.target <<EOF
[Unit]
Description=Blueking target allowing to start/stop all blueking module instances at once

[Install]
WantedBy=multi-user.target
EOF

    systemctl -q enable blueking.target
fi

# adjust blueking user limits
if [[ -d /etc/security/limits.d/ ]]; then
    if ! grep -q blueking /etc/security/limits.d/bk-nofile.conf 2>/dev/null; then
        echo 'blueking soft nofile 204800' >> /etc/security/limits.d/bk-nofile.conf
        echo 'blueking hard nofile 204800' >> /etc/security/limits.d/bk-nofile.conf
        echo 'blueking soft nproc 10000' >> /etc/security/limits.d/bk-nofile.conf
        echo 'blueking hard nproc 10001' >> /etc/security/limits.d/bk-nofile.conf
    fi
else
    if ! grep -q blueking /etc/security/limits.conf 2>/dev/null; then
        echo 'blueking soft nofile 204800' >> /etc/security/limits.conf
        echo 'blueking hard nofile 204800' >> /etc/security/limits.conf
        echo 'blueking soft nproc 10000' >> /etc/security/limits.conf
        echo 'blueking hard nproc 10001' >> /etc/security/limits.conf
    fi
fi

# adjust systemd service Default openfile limits
sed -i -r '/^#?DefaultLimitNOFILE=/s/.*/DefaultLimitNOFILE=204800/' /etc/systemd/system.conf
systemctl daemon-reexec

# adjust kernel parameters
cat > /etc/sysctl.d/99-blueking.conf <<EOF
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 65536
net.core.netdev_max_backlog = 65536
net.core.rmem_max = 16777216  
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144
EOF
# reload sysctl config
sysctl --system

# SSH_CONNECTION contains four space-separated values: client IP
# address, client port number, server IP address, and server port number
if [[ -n "$SSH_CONNECTION" ]]; then
    TEST_IP=${SSH_CONNECTION/ *}
else
    TEST_IP="10.0.0.0"
fi
LAN_IP=$(ip route get "$TEST_IP" | grep -Po '(?<=src )(\d{1,3}\.){3}\d{1,3}')
LAN_IPV6=$(ip -6 addr show | awk '/inet6 .* scope global/{ split($2, ip_parts, "/"); print ip_parts[1]}')

if [[ -z "$LAN_IP" ]]; then
    echo "auto get LAN_IP failed, you can check <ip route get $TEST_IP> command output"
    echo "or create /etc/blueking/env/local.env file and input following line in it: "
    echo "LAN_IP=<your local private ip address>"
    exit 1
fi
# generate local.env contains static LAN_IP variables
if ! grep -q "LAN_IP=" /etc/blueking/env/local.env 2>/dev/null; then
    echo "LAN_IP=$LAN_IP" >> /etc/blueking/env/local.env
fi

if ! [[ -z "$LAN_IPV6" ]]; then
    echo "LAN_IPV6=$LAN_IPV6" >> /etc/blueking/env/local.env
fi

#if WAN_IP=$(curl -s --connect-timeout 2 http://ip.sb); then
#    if ! grep -q "WAN_IP=" /etc/blueking/env/local.env 2>/dev/null; then
#        echo "WAN_IP=$WAN_IP" >> /etc/blueking/env/local.env
#    fi
#else
#    echo "can't get WAN_IP" >&2
#fi

# 安装基础命令和基础包
COMMAND_RPM_LIST=(rsync jq expect uuid lsof)
COMMON_RPM_LIST=(openssl-devel readline-devel libcurl-devel libxml2-devel glibc-devel zlib-devel iproute sysvinit-tools procps-ng bind-utils bash-completion)
yum -y install "${COMMAND_RPM_LIST[@]}" "${COMMON_RPM_LIST[@]}"

rt=0
for cmd in "${COMMAND_RPM_LIST[@]}"; do 
    yum install -y "${cmd}"
    if ! command -v "$cmd" >/dev/null; then
        echo "$cmd is not found, yum install $cmd failed." >&2 
        ((rt++))
    fi
done

for rpm in "${COMMON_RPM_LIST[@]}"; do
    if ! rpm -q "${rpm}" > /dev/null 2>&1; then
        echo "$rpm is not installed, yum install $cmd failed." >&2 
        ((rt++))
    fi
done

exit "$rt"
# copy app.token file
# if [[ -s $CTRL_DIR/.app.token ]]; then
#     cp -a "$CTRL_DIR"/.app.token /etc/blueking/app_token.txt
# else
#     echo "no $CTRL_DIR/.app.token file found, plz check" >&2
# fi