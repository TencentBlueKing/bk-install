#!/usr/bin/env bash

gse_zk_addr="$1"
zkbin=/opt/zookeeper/bin/zkCli.sh
balancecfg='{"cpuk":0.1,"cpur":0.1,"cpup":10,"memk":0.3,"memr":0.3,"memp":104857,"diskk":0,"diskr":0,"diskp":10,"netk":0.6,"netr":0.6,"netp":10,"netdev":"eth1","weightmax":0.6}'
basecfg='{"pid":"logs","log":"logs","runmode":1,"alliothread":30,"level":"error","composeid":0,"enable_stream_remote":true,"datasvrip":"0.0.0.0","dataport":58625,"dftregid":"test","dftcityid":"test"}'
agentcfg='{"update_timeout":600,"probability_change":50,"probability_connect":0.5}'

if [[ -z "$gse_zk_addr" ]]; then
    echo "$0 zk.service.consul:2181"
    exit 1
fi

# test zk alive
if ! $zkbin -server "$gse_zk_addr" get /; then
    echo "can not connect to zk($gse_zk_addr)"
    exit 1
fi

# init gse base node
$zkbin -server "$gse_zk_addr" create /gse '""'
$zkbin -server "$gse_zk_addr" create /gse/config '""'
$zkbin -server "$gse_zk_addr" create /gse/config/ip2city '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/dbproxy '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/task '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/task/all '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/taskserver '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/taskserver/all '""'
$zkbin -server "$gse_zk_addr" create /gse/config/etc 'etc'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver 'dataserver'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/storage '""'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/storage/all '""'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/data '""'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/all 'all'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/all/balancecfg "$balancecfg"
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/all/basecfg "$basecfg"
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/all/agentcfg "$agentcfg"
$zkbin -server "$gse_zk_addr" create /gse/config/server/cacheapi '""'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/all/schedule '""'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/all/schedule/servers '""'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/dataserver/all/schedule/agentcfg '""'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/operserver '""'
$zkbin -server "$gse_zk_addr" create /gse/config/etc/operserver/all '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/elasticsearch '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/elasticsearch/127.0.0.1 8080
$zkbin -server "$gse_zk_addr" create /gse/config/data '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/procmgr '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/syncdata '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/configserver '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/configserver/etc '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/configserver/etc/channelid '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/configserver/etc/channelid/plats '""'
$zkbin -server "$gse_zk_addr" create /gse/config/server/configserver/etc/channelid/plats/bkmonitor '1'
$zkbin -server "$gse_zk_addr" create /gse/config/server/configserver/etc/channelid/plats/tgdp '0'
$zkbin -server "$gse_zk_addr" create /gse/config/server/configserver/etc/channelid/plats/iegdata '2'
$zkbin -server "$gse_zk_addr" create /gse/config/server/configserver/etc/channelid/plats/tglog '3'