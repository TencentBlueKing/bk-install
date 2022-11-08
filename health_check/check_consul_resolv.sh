#!/usr/bin/env bash
# 用途：检查基础环境，consul集群是否正常运行，域名解析是否配置了nameserver 127.0.0.1 

EXITCODE=0

ok () {
    echo "$@ [OK]"
}

fail () {
    echo "$@ [FAIL]" 1>&2
    exit 1
}

warning () {
    echo "$@ [FAIL]" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

if pgrep -x consul &>/dev/null; then
    ok "check_consul_process"
else
    fail "check_consul_process"
fi

if lsof -nP -c consul -a -iUDP:53 &>/dev/null; then
    ok "check_consul_listen_udp_53"
else
    fail "check_consul_listen_udp_53"
fi

if lsof -nP -c consul -a -iTCP:8500 &>/dev/null; then
    ok "check_consul_listen_tcp_8500"
else
    fail "check_consul_listen_tcp_8500"
fi

# get consul node name
listen_addr=$(lsof -c consul -nP -a -iTCP -sTCP:LISTEN | awk '$(NF-1) ~ /:8301$/ { print $(NF-1) } ')
node_name=$(consul members | awk -v addr="$listen_addr" '$2 ~ addr { print $1 }')
# filter by state and node name
warning_svc=$(curl -s http://127.0.0.1:8500/v1/health/state/warning | jq -r --arg node "$node_name" '.[] | select(.Node == $node) | .ServiceName')
critical_svc=$(curl -s http://127.0.0.1:8500/v1/health/state/critical | jq -r --arg node "$node_name" '.[] | select(.Node == $node) | .ServiceName')
if [[ -z "$warning_svc" ]]; then
    ok "check_consul_warning_svc" 
else
    warning "check_consul_warning_svc"
    echo -n "以下服务consul显示为warning，请确认: "
    echo "$critical_svc" | xargs
fi
if [[ -z "$critical_svc" ]]; then
    ok "check_consul_critical_svc" 
else
    warning "check_consul_critical_svc"
    echo -n "以下服务consul显示为critical，请确认: "
    echo "$critical_svc" | xargs
fi

mapfile -t ns < <(grep -Ev '^\s*#' /etc/resolv.conf | awk '/nameserver/ { print $2 }' )
if [[ ${ns[0]} = "127.0.0.1" ]]; then
    ok "check_resolv_conf_127.0.0.1"
else
    fail "check_resolv_conf_127.0.0.1"
fi

# 如果有传参数，则都当作需要检测的域名来处理
for domain in "$@"
do
    if [[ -z $(dig +short "$domain") ]]; then
        warning "$domain 解析为空，请检查对应进程是否启动。"
        echo "检查的方法如下：找到/etc/consul.d/service/下对应模块的服务定义文件"
        echo "根据检查的不同方法，如果是tcp探测，使用telnet检测是否监听。如果是脚本探测，运行脚本看输出和返回码"
    fi
done

exit "$EXITCODE"