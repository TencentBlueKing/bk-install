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

CONSUL_CRITICAL_SVC=$(curl -s http://127.0.0.1:8500/v1/health/state/critical)

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
while read -r svc node output; do
    event+=("$(gen_single_event_json "Consul critical service" "$node" "reason:<$output>" "service:$svc" )")
done < <(jq -r '.[] | [.ServiceName, .Node, .Output] | @tsv' <<<"$CONSUL_CRITICAL_SVC")

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
   msg=$(curl -s -X POST "$DATA_URL" -d "$json") 
   if ! [[ $msg = *success* ]]; then
      echo "report error"
      echo "$msg"
      exit 1
   else 
      echo "report success"
      exit 0
   fi
fi
