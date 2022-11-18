#!/usr/bin/env bash
# Description: 获取本机注册的服务的端口，然后根据模块名拼接对应的healthz的url，来判断是否健康

# 检查的服务名pattern，如果不传递，默认是所有匹配
HEALTHZ_SVC_PATTERN=${1:-.*}

TRUE="\e[1;32mtrue\e[0m"
FALSE="\e[1;31mfalse\e[0m"
RET=0

CURL_OPTS=(--silent --connect-timeout 2)

check_status_code () {
    local url=$1
    local expect_code=$2

    [[ $(curl "${CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "$url") -eq "$expect_code" ]]
}

check_response_keyword () {
    local url=$1
    local keyword=$2
    local response=$(curl -s "$url")
    if jq -e . &>/dev/null <<<"$response"; then
        response=$(jq -c . <<<"$response")
    fi
    [[ $response = *"${keyword}"* ]]
}

healthz_error_output () {
    local url=$1
    local resp
    resp=$(curl "${CURL_OPTS[@]}" "$url")
    if [[ $? -eq 7 ]]; then
        printf "connection refused"
    elif [[ -n "$resp" ]]; then 
        jq -c . 2>&1 <<<"$resp" 
    fi
}

# svc_name healthz_endpoint check_func expect 
SVC_CHECK_RULE=$(cat <<'EOF'
bkiam       /healthz    check_response_keyword   ok
bkssm       /healthz    check_response_keyword   ok
usermgr     /healthz/    check_status_code      200
paas-paas   /healthz/   check_status_code       200
paas-esb    /healthz/   check_status_code       200
paas-login  /healthz/   check_status_code       200
paas-console /console/healthz/ check_status_code 200
paas-apigw  /api/healthz/ check_status_code     200
paas-appengine /v1/healthz/ check_status_code   200
cmdb-admin  /healthz check_response_keyword  "ok":true,
cmdb-api    /healthz check_response_keyword  "ok":true,
cmdb-auth   /healthz check_response_keyword  "ok":true,
cmdb-cloud  /healthz check_response_keyword  "ok":true,
cmdb-core   /healthz check_response_keyword  "ok":true,
cmdb-datacollection /healthz check_response_keyword  "ok":true,
cmdb-event  /healthz check_response_keyword  "ok":true,
cmdb-host   /healthz check_response_keyword  "ok":true,
cmdb-operation  /healthz check_response_keyword  "ok":true,
cmdb-proc   /healthz check_response_keyword  "ok":true,
cmdb-task   /healthz check_response_keyword  "ok":true,
cmdb-topo   /healthz check_response_keyword  "ok":true,
cmdb-web    /healthz check_response_keyword  "ok":true,
cmdb-cache  /healthz check_response_keyword  "ok":true,
job-backup  /actuator/health    check_response_keyword  "status":"UP"
job-config  /actuator/health    check_response_keyword  "status":"UP"
job-crontab /actuator/health    check_response_keyword  "status":"UP"
job-execute /actuator/health    check_response_keyword  "status":"UP"
job-gateway-management  /actuator/health    check_response_keyword  "status":"UP"
job-logsvr  /actuator/health    check_response_keyword  "status":"UP"
job-manage  /actuator/health    check_response_keyword  "status":"UP"
bklog-api   /healthz/   check_response_keyword  "server_up":1
EOF
)

# 通过本机consul agent的http api生成三列tab分隔的文本信息
# COL1(服务名) COL2(ip address) COL3(port)
SVC_IP_PORT_MAP=$(curl -s http://127.0.0.1:8500/v1/agent/services | jq  -r 'keys[] as $k | .[$k] | [ .Service, .Address, .Port ] | @tsv'| sort -u)

# 通过join来合并check rule和注册svc的列
SVC_CHECK_ON_THIS_HOST=$(join -j 1 <(echo "$SVC_IP_PORT_MAP" | sort ) <(echo "$SVC_CHECK_RULE" | sort ))

# 通过服务名的匹配来拼接healthz接口的url地址
while read -r svc ip port healthz check_func expect; do 
    healthz=${healthz#/}    # 去掉开头的/ 如果有
    healthz_url=http://${ip}:${port}/${healthz}
    if $check_func "$healthz_url" "$expect"; then
        printf "%-45s: %-7b" "$svc($healthz_url)" "$TRUE"
    else
        printf "%-45s: %-7b" "$svc($healthz_url)" "$FALSE"
        printf " Reason: %s" "$(healthz_error_output "$healthz_url")"
        ((RET++))
    fi
    printf "\n"
done < <(awk -v pattern="$HEALTHZ_SVC_PATTERN" '$1 ~ pattern' <<<"$SVC_CHECK_ON_THIS_HOST")

exit "$RET"