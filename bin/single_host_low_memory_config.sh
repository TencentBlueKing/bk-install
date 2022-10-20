#!/usr/bin/env bash

# 要降低蓝鲸产品（blueking）账号运行的进程占用的内存大小，必须从2个方面：
# 1. 降低单个进程的内存消耗（主要能通过运维手段处理的只有jvm的参数了）
# 2. 降低进程组的个数（主要调整配置文件里workers的大小来限制）

. "$HOME"/.bashrc  # 获取 CTRL_DIR和BK_HOME变量

SUPPORT_MODULE=(job paas bk_sops bk_itsm bk_iam bk_user_manage bk_nodeman nodeman usermgr)

get_bk_svc_memory () {
    awk '/^rss /{split(FILENAME,a,"/"); print a[7], int($NF/1024/1024)}' \
        /sys/fs/cgroup/memory/system.slice/bk-*/memory.stat \
        | sort -k2 -nr | column -t
}

get_rss_sum_of_user () {
    local user=$1
    ps --no-header -u "$user" -o pmem,comm,pid,rss --sort -rss | awk '{ sum+=$NF }END{print sum/1024}'
}

sum_rss_of_module () {
    local module=$1
    local mem_total=$(awk -v m="bk-$module*" '$1 ~ m { sum+=$2 } END { print sum }' <<<"$(get_bk_svc_memory)")
    printf "%s %s MB\n" "$module" "$mem_total"
}

get_container_id_of_saas () {
    local saas=$1
    docker ps --no-trunc | awk -v saas="$saas-[0-9]+" '$NF ~ saas { print $1 }'
}

sum_rss_of_saas () {
    local saas id name
    saas=$(docker ps --no-trunc | awk -v saas="bk_[a-z_0-9]+-[0-9]+" '$NF ~ saas { print $1,$NF }')
    while read -r id name; do
        printf "%s(SaaS) %s MB\n" "${name%-*}" $(awk '/^rss / { print int($2/1024/1024) }' "/sys/fs/cgroup/memory/docker/$id/memory.stat")
    done <<<"$saas"
}

# 获取所有蓝鲸组件的rss，倒序排
get_all_bk_sorted_rss () {
    { 
    for m in iam ssm usermgr gse license paas cmdb job nodeman; do
        sum_rss_of_module "$m"
    done
    sum_rss_of_saas
    } | sort -k2 -nr | column -t
}

# 调整 Job的 jvm 参数
tweak_job () {
    echo "Change JAVA_OPTS in /etc/sysconfig/bk-job-*"
    sed -i '/JAVA_OPTS/c JAVA_OPTS="-Xms128m -Xmx128m"' /etc/sysconfig/bk-job-*
    sed -i '/JAVA_OPTS/s/128/64/' /etc/sysconfig/bk-job-config
    echo "Restart job process"
    systemctl restart bk-job.target
}

# 调整open_paas的uwsgi的个数，默认都2个，esb给4个，用户根据自己cpu情况可以修改。
tweak_paas () {
    sed -i '/^workers =/d' "$BK_HOME"/etc/uwsgi-open_paas-*.ini
    for f in "$BK_HOME"/etc/uwsgi-open_paas-*.ini; do 
        echo "workers = 1" >> "$f"
    done
    sed -i 's/^workers = [0-9][0-9]*/workers = 2/' "$BK_HOME"/etc/uwsgi-open_paas-esb.ini
    echo "Restart paas process"
    systemctl restart bk-paas.target 
}

# 调整sops的uwsgi个数
tweak_bk_sops () {
    local id=$(get_container_id_of_saas bk_sops)
    if [[ -n $id ]]; then
        echo "Adjust worker number in bk_sops container"
        docker exec "$id" sed -ri '\,/data/app/code/manage.py celery worker,s/-c [0-9]+/-c 2/' /data/app/conf/supervisord.conf 
        docker exec "$id" sed -ri '/^cheaper =/s/[0-9]+/1/' /data/app/conf/bk_sops.ini
        docker exec "$id" sed -ri '/^cheaper-initial =/s/[0-9]+/1/' /data/app/conf/bk_sops.ini
        docker exec "$id" sed -ri '/^workers/s/[0-9]+/4/' /data/app/conf/bk_sops.ini
        docker exec "$id" /cache/.bk/env/bin/supervisorctl -c /data/app/conf/supervisord.conf reload
    else
        echo "bk_sops may not running, skip"
    fi
}

# 调整ITSM的uwsgi个数
tweak_bk_itsm () {
    local id=$(get_container_id_of_saas bk_itsm)
    if [[ -n $id ]]; then
        echo "Adjust worker number in bk_itsm container"
        docker exec "$id" sed -ri '\,/data/app/code/manage.py celery worker,s/-c [0-9]+/-c 2/' /data/app/conf/supervisord.conf 
        docker exec "$id" sed -ri '/^workers/s/[0-9]+/1/' /data/app/conf/bk_itsm.ini
        docker exec "$id" /cache/.bk/env/bin/supervisorctl -c /data/app/conf/supervisord.conf reload
    else
        echo "bk_itsm may not running, skip"
    fi
}

# 调整bk_nodeman(SaaS)的uwsgi个数
tweak_bk_nodeman () {
    local id=$(get_container_id_of_saas bk_nodeman)
    if [[ -n $id ]]; then
        echo "Adjust worker number in bk_nodeman container"
        docker exec "$id" sed -ri '/^cheaper =/s/[0-9]+/1/' /data/app/conf/bk_nodeman.ini
        docker exec "$id" sed -ri '/^cheaper-initial =/s/[0-9]+/1/' /data/app/conf/bk_nodeman.ini
        docker exec "$id" sed -ri '/^workers/s/[0-9]+/4/' /data/app/conf/bk_nodeman.ini
        docker exec "$id" /cache/.bk/env/bin/supervisorctl -c /data/app/conf/supervisord.conf reload
    else
        echo "bk_nodeman may not running, skip"
    fi
}

# 调整bk_iam(SaaS)的uwsgi个数
tweak_bk_iam () {
    local id=$(get_container_id_of_saas bk_iam)
    if [[ -n $id ]]; then
        echo "Adjust worker number in bk_iam container"
        docker exec "$id" sed -ri '/^cheaper =/s/[0-9]+/1/' /data/app/conf/bk_iam.ini
        docker exec "$id" sed -ri '/^cheaper-initial =/s/[0-9]+/1/' /data/app/conf/bk_iam.ini
        docker exec "$id" sed -ri '/^workers/s/[0-9]+/4/' /data/app/conf/bk_iam.ini
        docker exec "$id" /cache/.bk/env/bin/supervisorctl -c /data/app/conf/supervisord.conf reload
    else
        echo "bk_iam may not running, skip"
    fi
}

# 调整bk_usermgr(SaaS)的uwsgi个数
tweak_bk_user_manage () {
    local id=$(get_container_id_of_saas bk_user_manage)
    if [[ -n $id ]]; then
        echo "Adjust worker number in bk_user_manage container"
        docker exec "$id" sed -ri '/^cheaper =/s/[0-9]+/1/' /data/app/conf/bk_user_manage.ini
        docker exec "$id" sed -ri '/^cheaper-initial =/s/[0-9]+/1/' /data/app/conf/bk_user_manage.ini
        docker exec "$id" sed -ri '/^workers/s/[0-9]+/4/' /data/app/conf/bk_user_manage.ini
        docker exec "$id" /cache/.bk/env/bin/supervisorctl -c /data/app/conf/supervisord.conf reload
    else
        echo "bk_user_manage may not running, skip"
    fi
}

# 调整usermgr后台的进程的个数
tweak_usermgr () {
    sed -ri '/concurrency=8/s/concurrency=[0-9]+/concurrency=2/' "$BK_HOME"/etc/supervisor-usermgr-api.conf
    sed -ri '/gunicorn wsgi/s/-w [0-9]+/-w 2/' "$BK_HOME"/etc/supervisor-usermgr-api.conf
    echo "restart bk-usermgr"
    systemctl restart  bk-usermgr
}

# 调整节点管理后台的进程个数
tweak_nodeman () {
    sed -ri '/gunicorn wsgi/s/-w [0-9]+/-w 2/' "$BK_HOME"/etc/supervisor-bknodeman-nodeman.conf
    sed -ri '/--autoscale=/s/--autoscale=[0-9]+,[0-9]+/--autoscale=2,1/' "$BK_HOME"/etc/supervisor-bknodeman-nodeman.conf
    echo "restart bk-nodeman"
    systemctl restart bk-nodeman
}

tweak_all () {
    for m in "${SUPPORT_MODULE[@]}"; do
        tweak_$m 
    done
}

fn_exists () { declare -F "$1" > /dev/null; }

usage () {
    echo "Usage:"
    echo "       $0 print           # 打印当前的内存消耗"
    echo "       $0 tweak <module>  # 调整<module>的配置并重启，降低内存消耗"
    echo "       $0 tweak all       # 调整所有支持调整的模块并重启进程，降低内存消耗"
    exit 0
}
case $1 in 
    print) get_all_bk_sorted_rss ;; 
    tweak) 
        if fn_exists "tweak_$2"; then
            # 首先获取当前blueking账号下的所有进程加起来的内存之和（sum(rss)）以MB表示(rss默认是kilobytes)
            echo "Before optimize: blueking user consumed RSS memory: $(get_rss_sum_of_user blueking) MB"
            echo "in Details:"
            get_all_bk_sorted_rss 
            echo '-----------------------------------------------'
            echo "tweak $2"
            tweak_$2
            echo '-----------------------------------------------'
            # 最后获取当前blueking账号下的所有进程加起来的内存之和（sum(rss)）以MB表示(rss默认是kilobytes)
            echo "After optimize: blueking user consumed RSS memory: $(get_rss_sum_of_user blueking) MB"
            echo "in Details:"
            get_all_bk_sorted_rss 

        else   
            echo "tweak_$2 function has not been implemented"
            echo "Supported: ${SUPPORT_MODULE[*]}"
            exit 1
        fi
        ;;
    *) usage ;;
esac

