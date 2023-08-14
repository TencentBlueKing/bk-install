#!/usr/bin/env bash
# 检查gse 后台server的运行

RUNNING="\e[1;32mrunning\e[0m"
FAILED="\e[1;31mfailed\e[0m"
ERROR="\e[1;33merror\e[0m"
LISTEN_ERROR="\e[1;33mport_not_listen\e[0m"

readarray -t GSE_ENABLED_MODULE < \
<( systemctl list-unit-files --state=enabled --type=service \
    | awk '/^bk-gse-[a-z]+\.service/ { sub(".service","",$1); print $1 }')

# 输出的列的顺序是按key的字母顺序，-p指定的顺序只是恰好满足字母顺序。
MAIN_PID_STATUS=$(systemctl show -p MainPID,Names,SubState "${GSE_ENABLED_MODULE[@]}" \
    | awk 'BEGIN{ RS=""; FS="\n" } { gsub(/[A-Za-z]+=/,""); print $1,$2,$3  }')

check_gse_worker () {
    local master_pid=$1
    local cnt=3 # cnt(s)内如果worker子进程时间戳不变化，说明稳定
    local rt=0
    local cpid cpid_ts cpid_ts_tmp

    while ((cnt > 0 )); do 
        if [[ $master_pid -eq 0 ]]; then
            # 在特殊情况下，systemd没有获取到MAINPID处于Exit状态时，返回为0，此时不应该去获取child pid
            return 2
        fi
        # find child pid
        cpid=$(pgrep -P "$master_pid")
        if [[ -z $cpid ]]; then
            rt=1
            break
        fi
        if [[ -z $cpid_ts ]]; then
            # 第一次获取
            cpid_ts=$(stat -c "%Y" "/proc/$cpid/")
        else
            # 后续获取
            cpid_ts_tmp=$(stat -c "%Y" "/proc/$cpid/")
            # 发生了重启
            if [[ $cpid_ts -ne $cpid_ts_tmp ]]; then 
                rt=1
                break
            fi
        fi
        sleep 1
        ((cnt--))
    done

    return $rt
}

declare -A SVC_PORT_MAP=(
    [gse-data]=28625
    [gse-procmgr]=52030
    [gse-task]=48673
    [gse-file]=28925
    [gse-cluster]=28668
)

check_gse_port_listen () {
    local pid=$1
    local svc=$2
    local port=${SVC_PORT_MAP[$svc]}
    local -a ports
    local listen_info listen_cnt rt=0

    if [[ -z $port ]]; then
        # 为空，不校验
        return 0
    fi
    if ! [[ $port =~ ^[0-9]+$ ]]; then
        # 不合法返回
        echo "$svc has invalid port"
        return 1
    fi
    listen_info=$(ss -tnlpu)
    IFS=',' read -r -a ports <<< "$port"
    for p in "${ports[@]}"; do
        listen_cnt=$(awk -v pid="$pid" -v port="$p" \
            'BEGIN { pid_p=",pid="pid","; port_p=":"port"$"} $NF ~ pid_p && $5 ~ port_p' <<<"$listen_info" | wc -l)

        if [[ $listen_cnt -eq 0 ]]; then
            ((rt++))
        fi
    done
    return "$rt"
}

# 都是running只说明master进程存活，我们继续判断子进程的启动时间戳是否一直在更新（不断重启）
while read -r mpid svc state; do
    svc=${svc%.service}
    if [[ $state = "running" ]]; then 
        if check_gse_worker "$mpid"; then
            cpid=$(pgrep -P "$mpid")
            if check_gse_port_listen "$cpid" "$svc"; then
                printf "%-15s: %-7b\n" "$svc" "$RUNNING"
            else
                printf "%-15s: %-7b\n" "$svc" "$LISTEN_ERROR"
            fi
        else
            printf "%-15s: %-7b\n" "$svc" "$ERROR"
        fi
    else
        printf "%-15s: %-7b\n" "$svc" "$FAILED"
    fi
done <<<"$MAIN_PID_STATUS" 