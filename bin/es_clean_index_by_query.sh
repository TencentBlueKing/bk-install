#!/usr/bin/env bash
# 清理elasticearch中的未按日期滚动的index内容，通过delete_by_query方法
# 用法：es_clean_index_by_query.sh <es_rest_url> index keep_days dateformat

usage () {
    echo "该脚本用来清理elasticsearch中没有使用日期滚动的索引。"
    echo ""
    echo "用法: `basename $0` <es_rest_url> index_name keep_days"
    echo "例如: `basename $0` http://es.service.consul:9200 esb_api_log_community 7"
    exit
}

if [ $# -ne 3 ]; then
    usage
    exit 1
fi

es_rest_url=$1
index_name=$2
keep_days=$3

if ! [[ $keep_days =~ ^[0-9]+$ ]]; then
    echo "第三个参数（保留天数）必须是正整数"
    usage
    exit 1
fi

# 检查该index_name是否存在
http_code=$(curl -o /dev/null -s -w "%{http_code}\n" -I -X HEAD "$es_rest_url/$index_name")
if [[ $http_code -ne 200 ]]; then 
    echo "index $index_name does not existing. Abort processing"
    exit
fi

# 计算需要保留的文档timestamp：unixtime + ms
save_day=$(date -d "$keep_days days ago" +%s%3N)

# 获取当前index的store size
cur_store_size=$(curl -s "$es_rest_url/_cat/indices/$index_name?h=index,store.size&bytes=gb?pretty")
echo "当前index占用磁盘信息：$cur_store_size"

# 调用接口删除
echo "start delete ${index_name} documents which are $keep_days ago. this may take a while..."
curl "$es_rest_url/${index_name}/_delete_by_query" \
    -s -X POST \
    -H "Content-Type: application/json;charset=UTF-8" \
    --data @<(cat <<EOF
{
    "query": {
        "range" : {
            "@timestamp" : {
                "lt" : "$save_day"
            }
        }
    }
}
EOF
)

echo ""
echo "当前index的document标记删除信息：" 
curl -s $es_rest_url/_cat/indices?v | awk 'NR==1 || /esb_api_log/'