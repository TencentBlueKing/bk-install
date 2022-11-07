#!/usr/bin/env bash
# 用途： 检查给定的ip列表的gse_agent的状态值和版本号
# 用法： cat ip.txt | ./check_agent_info.sh 
#        ./check_agent_info.sh < ip.txt 
#        echo "1:10.0.1.2" | ./check_agent_info.sh 
# 输入格式： 云区域id:内网IP，每行一个，如果某行不带云区域id，默认会补上0:，表示直连区域
# 输出格式： <IP> <alive> <version> <parent_ip> <parent_port>

SELF_DIR=$(dirname "$(readlink -f "$0")")

# default direct area
declare -r BK_CLOUD_ID=0
declare -r AGENT_STATUS_API=/api/c/compapi/v2/gse/get_agent_status/
declare -r AGENT_INFO_API=/api/c/compapi/v2/gse/get_agent_info/
declare -r ESB_API_METHOD=POST

declare -a hosts=()
while read -r line; do
    ip=${line#*:}
    if [[ $line =~ : ]]; then
            bk_cloud_id=${line%:*}
    else
            bk_cloud_id=$BK_CLOUD_ID
    fi
    printf -v entry '{"ip": "%s", "bk_cloud_id": %d}' "$ip" $bk_cloud_id
    hosts+=("$entry")
done

# join string to array
printf -v hosts_info "%s," "${hosts[@]}"
hosts_info=${hosts_info%,}

# construct query req
printf -v req_info '"hosts": [%s]' "$hosts_info"

[[ -n $DEBUG ]] && printf "%s\n" "$req_info"
if ! agent_status=$("$SELF_DIR"/esb_api_test.sh $ESB_API_METHOD $AGENT_STATUS_API "$req_info"); then
    echo "METHOD $AGENT_STATUS_API failed."
    echo "$agent_status"
    exit 1
fi
if ! agent_info=$("$SELF_DIR"/esb_api_test.sh $ESB_API_METHOD $AGENT_INFO_API "$req_info"); then
    echo "METHOD $AGENT_INFO_API failed."
    echo "$agent_info"
    exit 1
fi

{
printf "%s %s %s %s %s\n" "云区域:IP" "状态(1:存活;0:失联)" "版本号" "上级svr" "上级svr端口"
join -j 1 <(jq -r '.data | keys[] as $k | "\($k) \(.[$k] | .bk_agent_alive)"' <<<"$agent_status") \
        <(jq -r '.data | keys[] as $k | "\($k) \(.[$k] | .version) \(.[$k] |.parent_ip) \(.[$k] |.parent_port)"' <<<"$agent_info") 
} | column -t -s ' '
