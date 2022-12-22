#!/usr/bin/env bash
# 参考etcd的官方安装教程编写的自动化安装脚本
# 用法：./install_etcd.sh ip1 ip2 ip3
# 注意事项：1. 请保证已经下载好etcd和etcdctl二进制，放到了系统的$PATH下
#           2. 三台ip需要并发执行相同的命令，否则systemctl start etcd时会卡住

# 确定所需环境变量
ETCD_CLIENT_PORT=${ETCD_CLIENT_PORT:-2379}
ETCD_PEER_PORT=${ETCD_PEER_PORT:-2380}
ETCD_CLUSTER_TOKEN=${ETCD_CLUSTER_TOKEN:-etcd-cluster-token}
PROTOCOL=${PROTOCOL:-http}	# 是否启用tls加密连接，默认不加密（http），加密请用环境变量覆盖为https

# 集群IP信息是作为命令行参数传入
etcd_members=( $@ )
etcd_members_num=${#etcd_members[@]}

# 检查 ${#etcd_members[@]}数是否满足奇数且<=7
echo "etcd number: $etcd_members_num"
if ! [[ $etcd_members_num -eq 1 || $etcd_members_num -eq 3 || $etcd_members_num -eq 5 || $etcd_members_num -eq 7 ]]; then
    echo "传入的etcd ip数量不满足要求, 建议生产环境使用3,5,7奇数台etcd"
    exit 1
fi

MY_IP_ADDRESS=$(ip route get "$1" | grep -Po '(?<=src )(\d{1,3}\.){3}\d{1,3}' | head -1) 
ETCD_LISTEN_IP_ADDRESS=${MY_IP_ADDRESS:-127.0.0.1}

# 计算初始的etcd集群列表字符串，以及本机的ETCD_NAME
ETCD_INITIAL_CLUSTER=''
for ((idx=0; idx<etcd_members_num; idx++)); do
    if [[ ${etcd_members[$idx]} = "$MY_IP_ADDRESS" ]]; then
	ETCD_NAME=etcd${idx}
    fi
    ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER},etcd${idx}=$PROTOCOL://${etcd_members[$idx]}:$ETCD_PEER_PORT"
done
# 去掉行首的一个英文逗号
ETCD_INITIAL_CLUSTER=${ETCD_INITIAL_CLUSTER#,}

# 如果获取ETCD_NAME失败，传参或者自动获取本机IP有问题，需要人工干预
if [[ -z $ETCD_NAME ]]; then
    echo "获取本机的ETCD_NAME失败，请确认\'ip get route $1\'命令输出的ip在脚本命令行参数中"
    exit 2
fi

# 创建目录
ETCD_CERT_PATH=${ETCD_CERT_PATH:-/etc/ssl/etcd}
ETCD_DATA_DIR=${ETCD_DATA_DIR:-/var/lib/etcd}
[[ -d "$ETCD_DATA_DIR" ]] && mkdir -p "$ETCD_DATA_DIR"
[[ -d "$ETCD_CERT_PATH" ]] && mkdir -p "$ETCD_CERT_PATH"

chown -R blueking.blueking "$ETCD_CERT_PATH"

# 写入环境变量文件
if [[ $PROTOCOL = "https" ]]; then
    cat > /etc/sysconfig/etcd-ssl <<EOF
#[Etcdctl]
ETCDCTL_CA_FILE=$ETCD_CERT_PATH/etcd-ca.pem
ETCDCTL_CERT_FILE=$ETCD_CERT_PATH/${ETCD_NAME}.pem
ETCDCTL_KEY_FILE=$ETCD_CERT_PATH/${ETCD_NAME}-key.pem

#[Security]
ETCD_CLIENT_CERT_AUTH=true
ETCD_TRUSTED_CA_FILE=$ETCD_CERT_PATH/etcd-ca.pem
ETCD_CERT_FILE=$ETCD_CERT_PATH/${ETCD_NAME}.pem
ETCD_KEY_FILE=$ETCD_CERT_PATH/${ETCD_NAME}-key.pem
ETCD_PEER_CLIENT_CERT_AUTH=true
ETCD_PEER_TRUSTED_CA_FILE=$ETCD_CERT_PATH/etcd-ca.pem
ETCD_PEER_CERT_FILE=$ETCD_CERT_PATH/${ETCD_NAME}.pem
ETCD_PEER_KEY_FILE=$ETCD_CERT_PATH/${ETCD_NAME}-key.pem
EOF
fi

# 生成etcd的service unit文件
cat > /tmp/etcd.service <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos/etcd
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
Restart=always
RestartSec=5s
LimitNOFILE=40000
TimeoutStartSec=0
EnvironmentFile=-/etc/sysconfig/etcd-ssl

ExecStart=/usr/local/bin/etcd --name $ETCD_NAME \
  --data-dir $ETCD_DATA_DIR \
  --listen-client-urls $PROTOCOL://$ETCD_LISTEN_IP_ADDRESS:$ETCD_CLIENT_PORT,$PROTOCOL://127.0.0.1:$ETCD_CLIENT_PORT \
  --advertise-client-urls $PROTOCOL://$MY_IP_ADDRESS:$ETCD_CLIENT_PORT \
  --listen-peer-urls $PROTOCOL://$MY_IP_ADDRESS:$ETCD_PEER_PORT \
  --initial-advertise-peer-urls $PROTOCOL://$MY_IP_ADDRESS:$ETCD_PEER_PORT \
  --initial-cluster $ETCD_INITIAL_CLUSTER \
  --initial-cluster-state new \
  --initial-cluster-token $ETCD_CLUSTER_TOKEN \
  --auto-compaction-retention 1

[Install]
WantedBy=multi-user.target
EOF

mv /tmp/etcd.service /etc/systemd/system/etcd.service

# to start service
systemctl daemon-reload
systemctl enable etcd.service
systemctl start etcd.service
