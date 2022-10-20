#!/usr/bin/env bash
# 为CMDB部署Mongo-Connector: https://github.com/yougov/mongo-connector/wiki/Installation
# 需要先为mongodb replicaset集群创建一个供mongo-connector可以读取oplog的帐号。
# 参考以下WiKI文章：https://github.com/yougov/mongo-connector/wiki/Usage-with-Authentication
# 在蓝鲸体系下，登录mongodb所在机器后可以这样操作：
# source ./utils.fc 
# mongo -u $MONGODB_USER -p $MONGODB_PASS mongodb://mongodb.service.consul:27017/admin
# 连上后，使用以下命令创建账号：
# db.getSiblingDB("admin").createUser({
#       user: "mongo-connector",
#       pwd: "password",
#       roles: ["backup"]
#     })
# 创建账号后，用户名和密码，作为本脚本的参数传入。即：
# bash install_mongo_connector.sh mongo-connector password http://es.service.consul:10004

MONGODB_OP_USER=${1:-MONGODB_USER}
MONGODB_OP_PASS=${2:-MONGODB_PASS}
ES_URL=${3:-"http://es.service.consul:10004"}
MONGODB_HOST=${MONGODB_HOST:-mongodb.service.consul}
MONGODB_PORT=${MONGODB_PORT:-27017}
PYTHON3_EXE=${PYTHON_EXE:-/opt/py36/bin/python}

$PYTHON3_EXE -m venv "$INSTALL_PATH/.envs/mongo-connector"

source "$INSTALL_PATH/.envs/mongo-connector/bin/activate"

# mongo connector需要是3.1.1以上，否则会有bug
pip install elastic2-doc-manager elasticsearch
pip install 'mongo-connector[elastic5]>=3.1.1'
pip install pathlib2

# 请参考官方文档说明：https://github.com/yougov/mongo-connector/wiki/Configuration-Options
cat <<EOF > /etc/mongo-connector.json
{
    "__comment__": "Configuration options starting with '__' are disabled",
    "__comment__": "To enable them, remove the preceding '__'",

    "mainAddress": "$MONGODB_HOST:$MONGODB_PORT",
    "oplogFile": "mongo-connector-oplog.timestamp",
    "noDump": false,
    "batchSize": -1,
    "verbosity": 1,
    "continueOnError": true,
    "authentication": {
        "adminUsername": "$MONGODB_OP_USER",
        "password": "$MONGODB_OP_PASS"
    },

    "__fields": ["field1", "field2", "field3"],

    "exclude_fields": ["create_time", "last_time"],

    "namespaces": {
        "cmdb.cc_HostBase": true,
        "cmdb.cc_ApplicationBase": true,
        "cmdb.cc_ObjectBase": true,
        "cmdb.cc_ObjDes": true,
        "cmdb.cc_OperationLog": false
    },

    "docManagers": [
        {
            "docManager": "elastic2_doc_manager",
            "targetURL": "$ES_URL",
            "__bulkSize": 1000,
            "uniqueKey": "_id",
            "autoCommitInterval": 0
        }
    ]
}
EOF

cat <<EOF > /tmp/mongo-connector.service
[Unit]
Description=MongoDB Connector
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/bin/bash -c 'cd $INSTALL_PATH/.envs; source mongo-connector/bin/activate; mongo-connector -c /etc/mongo-connector.json --stdout'
Restart=always
Type=simple
StandardError=syslog
NotifyAccess=all

[Install]
WantedBy=multi-user.target
EOF

mv /tmp/mongo-connector.service /etc/systemd/system/mongo-connector.service

# to start service
systemctl daemon-reload
systemctl enable mongo-connector.service
systemctl start mongo-connector.service
