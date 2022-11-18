#!/usr/bin/env bash

check_nginx_conf () {
    /usr/local/openresty/nginx/sbin/nginx -t 
}

# 目前官方没有health接口，只能判断进程是否存活了
check_consul_template () {
    pgrep -x consul-template
}

if ! check_nginx_conf &>/dev/null ; then
    echo "please check nginx config syntax."
    check_nginx_conf 
    exit 1
fi

if ! check_consul_template >/dev/null ; then
    echo "consul-template process is not running"
    echo "You can run <systemctl restart consul-template> on this host and "
    echo "then check it with <systemctl status consul-template> command"
    exit 1
fi

echo "nginx check successful"
exit 0