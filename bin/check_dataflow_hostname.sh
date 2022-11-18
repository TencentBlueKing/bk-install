#!/usr/bin/env bash
# 检查部署了jobnavi和dataflow，以及hadoop的机器上是否可以解析各自的HOSTNAME
# dataflow需要用到consul域名解析节点，这样避免每台机器都配置/etc/hosts
#
# 如果脚本输出有异常，检查步骤如下：
# 0. 获取自己的hostname
# 1. consul members | grep 自己的IP地址 ，检查第一列名字和hostname是否匹配
#    如果不匹配，请使用hostnamectl set-hostname xxxx修改为和consul输出一致的名字。
# 2. 检查 /etc/resolv.conf 中是否有配置 search node.consul 这样一行。

source $CTRL_DIR/utils.fc

# get dataflow iplist
IPLIST=$(awk '/jobnavi|dataflow|hadoop/{ print $1 }'  $CTRL_DIR/install.config)

# get dataflow hosts hostname list
host_list=$({
for ip in $IPLIST; do
    ssh $ip 'hostname'
done
} | xargs )

for ip in $IPLIST; do
    ssh $ip "bash -s" <<EOF
for n in $host_list;
do
    if ! host \$n &>/dev/null; then
        echo \": \$n not resolved\"
    fi
done
EOF
done
