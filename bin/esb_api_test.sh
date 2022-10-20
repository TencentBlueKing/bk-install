#!/usr/bin/env bash
# 用途： 方便脚本测试和调用esb接口，构造curl的参数和部分公用的post json body
# 用法： ./esb_api_test.sh get /api/c/compapi/v2/usermanage/list_users/
#       ./esb_api_test.sh post /api/c/compapi/v2/gse/get_agent_status/ '"hosts": [{"ip": "10.0.0.1", "bk_cloud_id": 0}]' 
#       json body注意，它并不包含外层的{}，因为在脚本里已经补上了。

SELF_DIR=$(dirname "$(readlink -f "$0")")
CTRL_DIR=${CTRL_DIR:-$SELF_DIR/../}
SCRIPT_NAME=$(basename "$0")
if [[ $# -lt 2 ]]; then 
    echo "Usage: $SCRIPT_NAME <post|get> </api/for/esb/path> <json_body_exclude_common_fields>"
    exit 1
fi

if [[ -r ${SELF_DIR}/../load_env.sh ]]; then
    . ${SELF_DIR}/../load_env.sh 
fi
declare -x METHOD="${1^^}"
declare -x API_URL="$2"
declare -x JSON_PAYLOAD="$3"

declare -rx ESB_API_HOST=paas.service.consul
declare -rx BK_APP_CODE=${BK_PAAS_APP_CODE:-"bk_paas"}
declare -rx BK_APP_SECRET=${BK_PAAS_APP_SECRET}
declare -rx BK_APP_SECRET
declare -rx BK_USERNAME="admin"

declare -a CURL_OPTIONS=('-s')

if [[ -z "$BK_APP_SECRET" ]]; then
    echo "Please check BK_PAAS_APP_SECRET env variables is defined"
    exit 1
fi

TMP_JSON=$(mktemp /tmp/esb_api_test_XXXX.json)
trap 'cleanup $TMP_JSON' TERM EXIT
cleanup () {
    for f in "$@";do 
        if [[ -n "$DEBUG" ]]; then
            [[ -s "$f" ]] && cat "$f"
        fi
        rm -f "$f"
    done
}

if [[ -n $DEBUG ]]; then
    CURL_OPTIONS+=('-v')
fi


if [[ "$METHOD" = "POST" && -n "$JSON_PAYLOAD" ]]; then
    CURL_OPTIONS+=('-H' "Content-Type: application/json")
    cat > "$TMP_JSON" <<EOF
{
    "bk_app_code": "$BK_APP_CODE",
    "bk_app_secret": "$BK_APP_SECRET",
    "bk_supplier_account": "0",
    "bk_username": "$BK_USERNAME",
    $JSON_PAYLOAD
}
EOF
    RESPONSE=$(curl "${CURL_OPTIONS[@]}" -X "$METHOD" http://$ESB_API_HOST/"$API_URL" --data @"$TMP_JSON")
elif [[ "$METHOD" = "GET" && -z "$JSON_PAYLOAD" ]]; then
    RESPONSE=$(curl "${CURL_OPTIONS[@]}" -X "$METHOD" "http://$ESB_API_HOST/$API_URL/?bk_app_code=$BK_APP_CODE&bk_app_secret=$BK_APP_SECRET&bk_username=$BK_USERNAME")
elif [[ "$METHOD" = "GET" && -n "$JSON_PAYLOAD" ]]; then
    RESPONSE=$(curl "${CURL_OPTIONS[@]}" -X "$METHOD" "http://$ESB_API_HOST/$API_URL/?bk_app_code=$BK_APP_CODE&bk_app_secret=$BK_APP_SECRET&bk_username=$BK_USERNAME&$JSON_PAYLOAD")
else
    echo "unknown method"
    exit 2
fi

if [[ $(jq .result <<<"$RESPONSE") = "true" ]]; then
    echo "$RESPONSE"
else
    echo "call api failed. the response is:" >&2
    echo "$RESPONSE"
    exit 1
fi
