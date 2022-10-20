#!/usr/bin/env bash
# 查询cmdb在zookeeper上的注册的配置内容，并和本地配置目录文件比对md5sum

set -euo pipefail

INSTALL_PATH=${INSTALL_PATH:-/data/bkee}
CTRL_DIR=${CTRL_DIR:-/data/install}
ZKCLI=${CTRL_DIR}/bin/bk_zkcli.sh

CMDB_MIGRATE_CONF=${1:-$INSTALL_PATH/cmdb/server/conf/migrate.yaml}

if ! [[ -r $CMDB_MIGRATE_CONF ]]; then
    echo "$CMDB_MIGRATE_CONF is not readable"
    exit 1
fi

CMDB_CONF_DIR=$(awk '/^confs/ {getline; print $NF; exit 0}' "$CMDB_MIGRATE_CONF")

if ! [[ -d $CMDB_CONF_DIR ]]; then
    echo "parse $CMDB_MIGRATE_CONF error. please check confs.dir parameter"
    exit 1
fi

readarray -t CONFIG_NAME < <($ZKCLI -m cmdb -f "$CMDB_MIGRATE_CONF" -a -c "lsr /cc/services/config")
if [[ ${#CONFIG_NAME[@]} -eq 0 ]]; then
    echo "there is no config entry under /cc/services/config in cmdb zookeeper"
    exit 1
fi

RT=0
for entry in "${CONFIG_NAME[@]}"; do
    file="$CMDB_CONF_DIR/${entry}.yaml"
    content="$($ZKCLI -m cmdb -f "$CMDB_MIGRATE_CONF" -a -c "get /cc/services/config/$entry")"
    # sed to append newline
    if ! diff --strip-trailing-cr <( printf %s "$content") <( printf %s "$(<$file)") &> /dev/null; then
        echo "$file: FAILED"
        diff --strip-trailing-cr <( printf %s "$content") <( printf %s "$(<$file)") || true
        ((RT++))
    else 
        echo "$file: OK"
    fi
done

exit "$RT"