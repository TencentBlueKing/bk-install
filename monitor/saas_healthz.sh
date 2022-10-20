#!/usr/bin/env bash
# shellcheck disable=SC1091,SC1090

# 蓝鲸监控上申请的自定义事件DATA_ID
DATA_ID="$1"
# 蓝鲸监控上申请的自定义事件DATA_TOKEN
DATA_TOKEN="$2"
# 蓝鲸监控上对应的自定义事件上报URL
DATA_URL="$3"
# 环境标签（默认为prod，正式环境）
TAG=${4:-prod}

# SaaS app_code and skip auth api url
declare -A api=(
    ["bk_monitorv3"]="/api/status/business/"
    ["bk_log_search"]="/healthz/"
    ["bk_sops"]="/core/healthz"
    ["bk_itsm"]="/openapi/ticket/callback_failed_ticket/"
    ["bk_iam"]="/healthz"
    ["bk_nodeman"]="/ping"
)

declare -A SAAS_HEALTH=()

# get inner paas domain
source $HOME/.bashrc
source $CTRL_DIR/load_env.sh 

for code in "${!api[@]}"; do
    if [[ $(curl -m 5 -s -o /dev/null -L -w "%{http_code}\n" "$BK_PAAS_PRIVATE_URL/o/$code/${api[$code]}" ) -eq 200 ]]; then
        SAAS_HEALTH[$code]="true"
    else
        SAAS_HEALTH[$code]="false"
    fi
done

gen_single_event_json () {
    local event_name=$1
    local target=$2
    local event_content=$3
    local dimension=$4
    local timestamp
    timestamp=$(date +%s%3N)
    local dimension_key=${dimension%%:*}
    local dimension_value=${dimension##*:}
    cat <<EOF
{
  "event_name": "$event_name",
  "target": "$target",
  "event": {
      "content":"$event_content"
  },
  "dimension": {
      "env": "$TAG",
      "$dimension_key":"$dimension_value"
  },
  "timestamp": $timestamp
}
EOF
}

event=()
for m in "${!SAAS_HEALTH[@]}"; do
    if [[ ${SAAS_HEALTH[$m]} = false ]]; then
        event+=("$(gen_single_event_json "Blueking healthz check failed" "$LAN_IP-$HOSTNAME" "SaaS($m) failed" "SaaS:$m")")
    fi
done

if [[ ${#event[@]} -gt 0 ]]; then
    printf -v event_str "%s," "${event[@]}"
    event_str="[${event_str%,}]"
    json=$(cat <<EOF
{
    "data_id": ${DATA_ID},
    "access_token": "${DATA_TOKEN}",
    "data": $event_str
}
EOF
)

   echo "$json"
   msg=$(curl -m 5 -s -X POST "$DATA_URL" -d "$json") 
   if ! [[ $msg = *success* ]]; then
      echo "report error"
      echo "$msg"
      exit 1
   else 
      echo "report success"
      exit 0
   fi
fi
