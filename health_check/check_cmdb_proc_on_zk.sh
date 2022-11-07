#!/usr/bin/env bash
# 查询command在zookeeper上的注册信息，确定是否注册正常

INSTALL_PATH=${INSTALL_PATH:-/data/bkee}
CMDB_MIGRATE_CONF=${1:-$INSTALL_PATH/cmdb/server/conf/migrate.yaml}
CTRL_DIR=${CTRL_DIR:-/data/install}
ZKCLI=${CTRL_DIR}/bin/bk_zkcli.sh

_to_url () {
    jq -r '.scheme  +"://"+.ip+":"+(.port|tostring)'
}

ENDPOINTS=$($ZKCLI -m cmdb -f $CMDB_MIGRATE_CONF -a -c "lsr /cc/services/endpoints")
for entry in $ENDPOINTS; do
    if [[ $entry = */* ]]; then
        printf "%s %s\n" "${entry%/*}" "$($ZKCLI -m cmdb -f "$CMDB_MIGRATE_CONF" -a -c "get /cc/services/endpoints/$entry" | _to_url)"
    fi
done
