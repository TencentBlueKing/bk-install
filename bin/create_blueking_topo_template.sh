#!/usr/bin/env bash

SELF_DIR=$(readlink -f $(dirname $0))
ESB_API_TOOL=$SELF_DIR/esb_api_test.sh
BLUEKING_BIZ_ID=2	# 蓝鲸的业务ID，默认为2

declare -rA CC_API=(
    ["LIST_SET_TEMPLATE"]=/api/c/compapi/v2/cc/list_set_template/
    ["CREATE_SET_TEMPLATE"]=/api/c/compapi/v2/cc/create_set_template/
    ["LIST_SERVICE_TEMPLATE"]=/api/c/compapi/v2/cc/list_service_template/
    ["LIST_SET_TEMPLATE_RELATED_SERVICE_TEMPLATE"]=/api/c/compapi/v2/cc/list_set_template_related_service_template/
    ["UPDATE_SET_TEMPLATE"]=/api/c/compapi/v2/cc/update_set_template/
)

convert_list_to_regex_pattern () {
    local pattern
    pattern=$(printf "%s|" "$@")
    pattern=${pattern%|}
    pattern=$(printf "^(%s)$" $pattern)
    echo "$pattern"
}

create_set_tpl () {
    local biz_id name ids req
    biz_id=$1
    name=$2
    ids=$3
    req=$(printf '"name": "%s", "bk_biz_id": %d, "service_template_ids": [%s]' "$name" "$biz_id" "$ids")
    resp=$($ESB_API_TOOL POST "${CC_API["CREATE_SET_TEMPLATE"]}" "$req")
    if [[ $(jq -r '.code' <<<"$resp") -eq 0 ]]; then
        jq -r '.data.id' <<<"$resp"
        return 0
    else
        echo "$resp"
        return 1
    fi
}

# 获取当前业务的服务模板列表
CUR_SVC_TPL=$($ESB_API_TOOL POST "${CC_API["LIST_SERVICE_TEMPLATE"]}" "\"bk_biz_id\": $BLUEKING_BIZ_ID" | jq -r ' .data.info[] | [.id,.name] | @tsv')
# 获取当前业务的集群模板列表
CUR_SET_TPL=$($ESB_API_TOOL POST "${CC_API["LIST_SET_TEMPLATE"]}" "\"bk_biz_id\": $BLUEKING_BIZ_ID" | jq -r ' .data.info[] | [.id,.name] | @tsv')

# 从配置读取生成数组
TOPO_TPL=$1
if ! [[ -r $TOPO_TPL ]]; then
    echo "Usage: $0 <topo_tpl_file>"
    exit 1
fi

if [[ $(awk -F'\t' '/^[^#]/ || /^[^ *]$/ {print NF} ' "$TOPO_TPL" | sort -u) -ne 2 ]]; then
    echo "$TOPO_TPL文件中，配置的集群模板校验，并不是2列"
    exit 2
fi

# 校验是否包含key
TOPO_NAME=( $(grep -Ev '^#|^\s*$' "$TOPO_TPL" | sed -n '2,$p' | awk '{print $1}' | sort -u) )
if [[ ${#TOPO_NAME[@]} -eq 0 ]]; then
    echo "$TOPO_TPL 模板行为空"
    exit 3
fi

# 使用eval定义
eval "$(grep -Ev '^#|^\s*$' "$TOPO_TPL" | sed -n '2,$p' | awk '{a[$1]=a[$1]" "$2}END{ for (k in a) print "declare -a "k"=(" a[k] ")"}')"

for topo in "${TOPO_NAME[@]}"; do
    svr_tpl=${topo}[@]
    svr_tpl_regex=$(convert_list_to_regex_pattern "${!svr_tpl}")
    # 获取集群模板下的服务模板的id列表
    svr_tpl_ids=( $(awk -v regex=$svr_tpl_regex '$2 ~ regex { print $1 }' <<<"$CUR_SVC_TPL") )
    svr_tpl_ids_comma=$(printf "%s," "${svr_tpl_ids[@]}")
    svr_tpl_ids_comma=${svr_tpl_ids_comma%,}

    # 判断当前集群模板名是否存在，否则创建它
    if ! grep -qw "$topo" <<<"$CUR_SET_TPL"; then
        set_tpl_id=$(create_set_tpl $BLUEKING_BIZ_ID "$topo" "${svr_tpl_ids[@]}")
        if [[ $? -eq 0 ]]; then
            echo "create $topo($set_tpl_id) 集群模板成功"
        fi
    else
        set_tpl_id=$(awk -v name="$topo" '$2 == name { print $1 }' <<<"$CUR_SET_TPL")
    fi

    # 处理集群模板的更新
    if [[ $set_tpl_id =~ ^[0-9]+$ ]]; then
        # 检查集群模板下的服务模板数量是否和期望的一致
        CUR_SET_TPL_RELATED_SVC_TPL=$($ESB_API_TOOL POST "${CC_API["LIST_SET_TEMPLATE_RELATED_SERVICE_TEMPLATE"]}" "\"bk_biz_id\": $BLUEKING_BIZ_ID, \"set_template_id\": $set_tpl_id" | jq -r '.data[] | [.id,.name] | @tsv')

        # 数量不一致时需要调用更新接口
        if [[ ${#svr_tpl_ids[@]} -ne $(wc -l <<<"$CUR_SET_TPL_RELATED_SVC_TPL") ]]; then
            resp=$($ESB_API_TOOL POST "${CC_API["UPDATE_SET_TEMPLATE"]}" "\"bk_biz_id\": $BLUEKING_BIZ_ID, \"name\": \"$topo\", \"set_template_id\": $set_tpl_id, \"service_template_ids\": [$svr_tpl_ids_comma]")
           if [[ $(jq -r '.code' <<<"$resp") -eq 0 ]]; then
               echo "update $topo($set_tpl_id) successful"
           else
               echo "update $topo($set_tpl_id) failed"
               echo "$resp"
           fi
        else
           echo "$topo($set_tpl_id) set template is already up to date"
        fi
    else
        echo "create set tpl failed"
        echo "$set_tpl_id"
    fi
done