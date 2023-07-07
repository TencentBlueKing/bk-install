#!/usr/bin/env bash

set -euo pipefail
SELF_DIR=$(dirname "$(readlink -f "$0")")

# 加载环境变量
. $SELF_DIR/../load_env.sh

gse_zk_addr="$BK_GSE_ZK_HOST"
zkbin=/opt/zookeeper/bin/zkCli.sh
bk_biz_id=2 # 《蓝鲸》业务id，默认为2

if [[ -z "$gse_zk_addr" ]]; then
    echo "BK_GSE_ZK_HOST 变量为空，无法自动确认gse的zk地址" >&2
    exit 1
fi

# test zk alive
if ! $zkbin -server "$gse_zk_addr" get /; then
    echo "can not connect to zk($gse_zk_addr)" >&2
    exit 1
fi

# create dataid for snapshot
redis_storage="[{\"type\":1,\"biz_id\":$bk_biz_id,\"cluster_index\":1,\"data_set\":\"snapshot\",\"msg_system\":4,\"partition\":0}]"

$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/data/1001 "$redis_storage"

# create redis storage
redis_host="[{\"host\":\"$BK_CMDB_REDIS_HOST\",\"port\":$BK_CMDB_REDIS_PORT,\"type\":4,\"passwd\":\"$BK_CMDB_REDIS_PASSWORD\",\"mastername\":\"$BK_CMDB_REDIS_MASTER_NAME\"}]"
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/storage/all/0_1 "$redis_host"
$zkbin -server "$gse_zk_addr" set /gse/config/etc/dataserver/storage/all/0_1 "$redis_host"
