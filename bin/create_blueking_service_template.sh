#!/usr/bin/env bash

SELF_DIR=$(readlink -f "$(dirname "$0")")
ESB_API_TOOL=$SELF_DIR/esb_api_test.sh
BLUEKING_BIZ_ID=2    # 蓝鲸的业务ID，默认为2

declare -rA CC_API=(
    ["LIST_SERVICE_TEMPLATE"]=/api/c/compapi/v2/cc/list_service_template/
    ["CREATE_SERVICE_TEMPLATE"]=/api/c/compapi/v2/cc/create_service_template/
    ["LIST_PROC_TEMPLATE"]=/api/c/compapi/v2/cc/list_proc_template/
    ["CREATE_PROC_TEMPLATE"]=/api/c/compapi/v2/cc/batch_create_proc_template/
    ["UPDATE_PROC_TEMPLATE"]=/api/c/compapi/v2/cc/update_proc_template/
)

declare -A BIND_IP=(
    ["127.0.0.1"]=1
    ["0.0.0.0"]=2
)
declare -A PROTOCOL=(
    ["TCP"]=1
    ["UDP"]=2
)

create_service_template () {
    local id name resp
    name=$1
    resp=$($ESB_API_TOOL POST "${CC_API["CREATE_SERVICE_TEMPLATE"]}" \
    "\"bk_biz_id\": $BLUEKING_BIZ_ID, \"service_category_id\": 2, \"name\": \"$name\"")
    if [[ $(jq -r .code <<<"$resp") -eq 0 ]]; then
        jq -r .data.id <<<"$resp"
        return 0
    else
        echo "$resp"
        return 1
    fi
}

get_proc_tpl_list () {
    local svc_tpl_id=$1
    $ESB_API_TOOL POST "${CC_API["LIST_PROC_TEMPLATE"]}" "\"bk_biz_id\": $BLUEKING_BIZ_ID, \"service_template_id\": $svc_tpl_id" \
        | jq -r '.data.info[] | [ .id, .bk_process_name ] | @tsv'
}

PROCESS_TPL=$1
if ! [[ -r $PROCESS_TPL ]]; then
    echo "Usage: $0 <process_tpl_file>"
    exit 1
fi

if [[ $(awk -F'\t' '/^[^#]/ || /^[^ *]$/ {print NF} ' "$PROCESS_TPL" | sort -u) -ne 7 ]]; then
    echo "$PROCESS_TPL文件中，配置的进程模板校验，并不是7列"
    exit 2
fi

CUR_SVC_TPL=$($ESB_API_TOOL POST "${CC_API["LIST_SERVICE_TEMPLATE"]}" "\"bk_biz_id\": $BLUEKING_BIZ_ID" | jq -r ' .data.info[] | [.id,.name] | @tsv')
while IFS=, read -r service_template bk_func_name bk_process_name bk_start_param_regex bind_ip port protocol; do
    # 转化参数
    if [[ -z $bind_ip ]]; then
        bind_ip_value=""
    else
        bind_ip_value=${BIND_IP[$bind_ip]}
    fi
    protocol_value=${PROTOCOL[$protocol]}

    # 创建或获取服务模板
    if ! grep -qw "$service_template" <<<"$CUR_SVC_TPL"; then
        svc_tpl_id=$(create_service_template "$service_template")
        if [[ $? -eq 0 ]]; then
            echo "创建服务模板 $service_template($svc_tpl_id) 成功"
        fi
    else
        svc_tpl_id=$(awk -v name="$service_template" '$2 == name { print $1 }' <<<"$CUR_SVC_TPL")
    fi

    # 创建或打印进程模板
    if [[ $svc_tpl_id =~ ^[0-9]+$ ]]; then
        CUR_PROC_TPL="$(get_proc_tpl_list "$svc_tpl_id")"
        proc_tpl_id=$(awk -v name="$bk_process_name" '$2 == name { print $1 }' <<<"$CUR_PROC_TPL")
        if ! [[ $proc_tpl_id =~ ^[0-9]+$ ]]; then
            resp=$($ESB_API_TOOL POST "${CC_API["CREATE_PROC_TEMPLATE"]}" \
                  "\"bk_biz_id\": $BLUEKING_BIZ_ID, \"service_template_id\": $svc_tpl_id, \"processes\": [{\"spec\":{\"bk_func_name\": {\"as_default_value\": true,\"value\": \"$bk_func_name\"},\"bk_process_name\": {\"as_default_value\": true,\"value\": \"$bk_process_name\"},\"bk_start_param_regex\": {\"as_default_value\": true,\"value\": \"$bk_start_param_regex\"},\"bind_ip\": {\"as_default_value\": true,\"value\": \"$bind_ip_value\"},\"port\": {\"as_default_value\": true,\"value\": \"$port\"},\"protocol\": {\"as_default_value\": true,\"value\": \"$protocol_value\"}}}]")
            if [[ $(jq -r '.code' <<<"$resp") -eq 0 ]]; then
                echo "create $service_template($(jq -r '.data[]' <<<"$resp")) process template done" 
            else
                echo "create $service_template process template failed. response is $(jq -r -c <<<"$resp")"
            fi
        else
            # 这种情况下存在进程模板，需要调用更新接口
            resp=$($ESB_API_TOOL POST "${CC_API["UPDATE_PROC_TEMPLATE"]}" \
                  "\"bk_biz_id\": $BLUEKING_BIZ_ID, \"process_template_id\": $proc_tpl_id, \"process_property\": {\"bk_func_name\": {\"as_default_value\": true,\"value\": \"$bk_func_name\"},\"bk_process_name\": {\"as_default_value\": true,\"value\": \"$bk_process_name\"},\"bk_start_param_regex\": {\"as_default_value\": true,\"value\": \"$bk_start_param_regex\"},\"bind_ip\": {\"as_default_value\": true,\"value\": \"$bind_ip_value\"},\"port\": {\"as_default_value\": true,\"value\": \"$port\"},\"protocol\": {\"as_default_value\": true,\"value\": \"$protocol_value\"}}")
            if [[ $(jq -r '.code' <<<"$resp") -eq 0 ]]; then
                echo "update $bk_process_name($proc_tpl_id) process template done"
            else
                echo "update $bk_process_name($proc_tpl_id) process template failed. response is $(jq -r -c <<<"$resp")"
            fi
        fi
    else
        echo "create service template for $service_template failed."
        echo "$svc_tpl_id"
    fi
done < <(grep -Ev '^#|^\s*$' "$PROCESS_TPL" | sed -n '3,$p' | tr '\t' ,)