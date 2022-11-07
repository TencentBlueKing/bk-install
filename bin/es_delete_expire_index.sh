#!/usr/bin/env bash
# 清理elasticearch中的按日期滚动的index
# 用法：es_index_cleanup.sh <es_rest_url> index_prefix keep_days dateformat

usage () {
    echo "该脚本用来清理elasticsearch中基于日期的索引。索引名的结尾必须包含日期格式形如：%Y-%m-%d"
    echo ""
    echo "用法: `basename $0` <es_rest_url> index_prefix keep_days [date_format}"
    echo "date_format 参数是可选的，默认为'%Y.%m.%d'"
    echo "例1: `basename $0` http://es.service.consul:9200 paas_app_log- 7"
    echo "例2: `basename $0` http://es.service.consul:9200 2_admin_test_ 10 %Y%m%d%h"
    exit
}

if [ $# -lt 3 ]; then
    usage
    exit 1
fi

es_rest_url=$1
index_prefix=$2
keep_days=$3
date_format=${4:-"%Y.%m.%d"}

if ! [[ $keep_days =~ ^[0-9]+$ ]]; then
    echo "第三个参数（保留天数）必须是正整数"
    usage
    exit 1
fi

# 获取当前时间的的unix time表达
cur_secs=$(date +%s)
# 计算需要保留的日期的最后一天，以secs计算
target_date_secs=$(( cur_secs - (keep_days * 86400) ))

while true; do 
    target_date_secs=$(( target_date_secs - 86400 ))
    target_date_str=$(date --date="@$target_date_secs" +$date_format)
    index_name=${index_prefix}${target_date_str}

    # 检查该index_name是否存在
    http_code=$(curl -o /dev/null -s -w "%{http_code}\n" -I -X HEAD "$es_rest_url/$index_name")
    if [[ $http_code -ne 200 ]]; then 
        echo "index $index_name does not existing. Abort processing"
        break
    fi

    # 如果存在则调用DELETE方法删除它
    http_code=$(curl -o /dev/null -s -w "%{http_code}\n" -X DELETE "$es_rest_url/$index_name")
    if [[ $http_code -eq 200 ]]; then
        echo "Successfully delete index $index_name"
    else
        echo "FAILED. delete method returns http code $http_code. Continue processing the next index."
        continue
    fi

    # 校验是否删除成功，应该返回404，如果返回200，则没有删除成功
    http_code=$(curl -o /dev/null -s -w "%{http_code}\n" -I -X HEAD "$es_rest_url/$index_name")
    if [[ $http_code -eq 200 ]]; then
        echo "FAILED. delete method returns successfully. but the index still exists. Continue processing the next index."
        continue
    fi
done