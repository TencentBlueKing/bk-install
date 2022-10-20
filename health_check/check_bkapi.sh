#!/usr/bin/env bash

set -euo pipefail

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
source "${SELF_DIR}"/../load_env.sh
source "${SELF_DIR}"/../functions

# PYTHON目录
PYTHON_PATH=/opt/py36/bin/python

# 需要安装的模块
MODULE=bkapi_check

# 需要验证的API模块
API_MODULE=$1

set -u
export BK_NGINX_HOST=$BK_NGINX_IP
export BK_PAAS_INNER_HOST=$BK_PAAS_PRIVATE_ADDR
export BK_CC_HOST=$BK_CMDB_IP:$BK_CMDB_WEB_PORT
export BK_JOB_HOST=$BK_JOB_IP:$BK_JOB_GATEWAY_SERVER_HTTP_PORT
export BK_PAAS_APP_CODE=$BK_PAAS_APP_CODE
export BK_PAAS_APP_SECRET=$BK_PAAS_APP_SECRET
export BK_PAAS_ADMIN_USERNAME=$BK_PAAS_ADMIN_USERNAME
export BK_PAAS_ADMIN_PASSWORD=$BK_PAAS_ADMIN_PASSWORD
export BK_PAAS_PUBLIC_HOST=$BK_PAAS_PUBLIC_ADDR
set +u

source "${PYTHON_PATH%/*}/virtualenvwrapper.sh"

emphasize "check ${MODULE} on host: $BK_NGINX_IP_COMMA"
if [[  "$API_MODULE" == "all" ]]; then
    workon "${MODULE}" && \
    python run.py
else
    workon "${MODULE}" && \
    python run.py "$API_MODULE"
fi
