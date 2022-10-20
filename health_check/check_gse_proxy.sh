#!/usr/bin/env bash

TAG="$1"
LOG_FILE=/tmp/debug/check_gse_proxy.log

[[ -d /tmp/debug ]] || mkdir -p /tmp/debug
exec &> >(tee $LOG_FILE)

# 获取agent日志
get_agent_latest_log () {
    cat $(ls -rt /var/log/gse/agent-$(date +%) | tail -1)
}

# get basic info 
pids=( $(pgrep -x agentWorker) )

count=${#pids[@]}

case $count in 
    0)
        echo "没有agentWorker信息，进一步查看"
        if ps -C gseMaster; then
            echo "agent在不断重启，需要通过agent的日志确认"
            get_agent_latest_log
            exit 1
        fi
        ;;
    1)
        echo "存在一个agentWorker进程"
        pid=${pids[0]}
        conf=$(ps --no-header -C agentWorker -o args | awk '{print $NF}')
        ;;
    *)
        echo "存在$count个agentWorker进程"
        ps -C agentWorker -o pid,ppid,lstart,args
        if [[ -n "$TAG" ]]; then
            echo "你选择了查看 $TAG 实例"
            conf=$(ps --no-header -C agentWorker -o pid,args | awk -v conf=$TAG '$NF ~ conf { print $NF }')
            pid=$(ps --no-header -C agentWorker -o pid,args | awk -v conf=$TAG '$NF ~ conf { print $1 }')
        else
            confs=( $(ps --no-header -C agentWorker -o args | awk '{print $NF}' ) )
            echo "请指定你需要查看哪个agentworker进程"
            conf_string="$(printf "%s|" "${confs[@]}")"
            printf "%s <%s>\n" "bash $0" "${conf_string%|}"
            exit 1
        fi
        ;;
esac

ps -p "$pid" -o pid,ppid,lstart,args
echo -n "配置文件路径为："
echo "$conf"
echo "配置文件内容为："
cat "$conf"

node_type=
if grep -q proxylistenip "$conf" 2>/dev/null; then
    node_type=proxy
fi

echo
echo "判断是否与gse task建立了48668连接"
netstat -antp | awk '$5 ~ /:48668/'

echo "列出gse_agent的所有进程端口:"
lsof -p $pid -a -nP -i

echo "列出本机所有syn-sent状态的（一般是网络策略问题会导致，一直处于该状态）:"
ss -n -p -t4 state syn-sent


echo "获取本机网卡地址:"
ip addr 
echo 

echo "获取本机访问外网的地址："
curl --connect-timeout 2 -s http://ip.sb
echo

if [[ $node_type = "proxy" ]]; then
    proxylistenip=$(awk -F'"' '/proxylistenip/{print $4}' $conf)
    proxy_agent_connect_task_ip=$(grep -A1 '"taskserver"' $conf | awk -F'"'  '/ip/ { print $4}')
    if [[ $proxylistenip != $proxy_agent_connect_task_ip ]]; then
        echo "proxylistenip的配置项和taskserver的配置不匹配"
    else
        if ! ip addr | awk -F'[ /]+' '/inet/{print $3}' | grep -wq "$proxy_agent_connect_task_ip"; then
            echo "$proxy_agent_connect_task_ip 不存在于服务器的网卡上"
        fi
    fi
fi

echo "日志过长无法截屏时，可以发送日志文件：$LOG_FILE 给技术支持人员。"