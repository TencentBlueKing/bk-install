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

# get enabled JOB service
JOB_MODULE=()
readarray -t JOB_MODULE < \
        <( systemctl list-unit-files --state=enabled --type=service \
                | awk '/^bk-job-[a-z]+\.service/ { sub(".service","",$1); print $1 }' | grep -v job-gateway)

# get job service port
source "$HOME/.bkrc"
declare -A JOB_PORT=()
while read -r svc port; do 
   JOB_PORT[$svc]=$port 
done < <(cd "$BK_HOME"/etc/job && \
        awk '/^  port:/ { svc=FILENAME; sub("application","job",svc); sub(".yml","",svc);print "bk-"svc,$NF}' application-*.yml)

declare -A JOB_HEALTH=()
# get LAN_IP & PORT 
source /etc/blueking/env/local.env
for m in "${JOB_MODULE[@]}"; do
    PORT=${JOB_PORT[$m]}
    if [[ $(curl -s "http://$LAN_IP:$PORT/actuator/health" | jq -r .status) = "UP" ]]; then
        JOB_HEALTH[$m]="true"
    else
        JOB_HEALTH[$m]="false"
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
for m in "${!JOB_HEALTH[@]}"; do
    if [[ ${JOB_HEALTH[$m]} = false ]]; then
        event+=("$(gen_single_event_json "Blueking healthz check failed" "$LAN_IP-$HOSTNAME" "$m failed" "service:$m")")
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
