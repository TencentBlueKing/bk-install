#!/usr/bin/env bash
# 检查部署蓝鲸后台的主机规范化检查，运行在每台主机上

export LC_ALL=C LANG=C
SELF_PATH=$(readlink -f "$0")
SELF_DIR=$(dirname $(readlink -f "$0"))

check_yum_repo () {
    local rt=0
    for pkg in consul-template rabbitmq-server openresty; do
        yum info "$pkg" &>/dev/null
        rt=$(( rt + $? ))
    done
    return "$rt"
}

check_centos_7 () {
   which systemctl &>/dev/null
}

# TOOD 其实要检查pip是否能更新到20.0.1版本，pip的版本会影响到pip包能否正确安装
check_pip_config () {
    return 0
}

# firewalld
# NetworkManager
check_systemd_service () {
   local svc=$1
   if systemctl is-active --quiet $svc ; then
      echo "$svc is running, you should shutdown $svc"
      return 1
   else
      return 0
   fi
}

check_firewalld () {
   check_systemd_service "firewalld"
}

check_selinux () {
    if [[ -x /usr/sbin/sestatus ]]; then
        if ! [[ $(/usr/sbin/sestatus -v | awk '/SELinux status/ { print $NF }') = "disabled" ]]; then
        return 1
        fi
    fi
    return 0
}

check_umask () {
   if ! [[ $(umask) = "0022" ]]; then
      echo "umask shouled be 0022, now is <$(umask)>."
      return 1
   fi
}

check_open_files_limit () {
    if [[ $(ulimit -n) = "1024" ]];then
      echo "ulimit open files (-n)  should not be default 1024"
      echo "increase it up to 102400 or more for all BK hosts"
      return 1
    fi
}

check_http_proxy () {
   if [[ -n "$http_proxy" ]]; then
       echo "http_proxy variable is not empty."
       echo "you should make sure http_proxy can proxy all traffic between blueking hosts"
       echo "and all *.service.consul domain"
       return 1
   fi
}

check_glibc_version () {
    local base_version=2.14
    if ! command -v rpmdev-vercmp &>/dev/null; then
        yum -q -y install rpmdevtools
    fi
    rpmdev-vercmp "$base_version" "$(rpm -q --queryformat "%{VERSION}" glibc-common)"
    case $? in
        0 | 12) return 0 ;;
        11 ) echo "glibc的版本低于2.14，不符合部署gse的最低要求" ;;
        * ) echo "未知错误" ;;
    esac
    return 1
}

# 检查consul节点运行
check_consul () {
    # 检查resolv.conf第一个nameserver是否为127.0.0.1
    if ! [[ $(awk '/^\s*nameserver/ { print $2 }' /etc/resolv.conf | head -1) = "127.0.0.1" ]]; then
        echo "/etc/resolv.conf的第一个dns server不是127.0.0.1"
        return 1
    fi
    # 检查consul是否运行并监听的53端口
    if ! [[ $(netstat -nlup | awk '$NF ~ /\/consul$/ && $4 ~ /:53$/' | wc -l) -eq 1 ]]; then
        echo "consul未监听53 dns端口"
        return 1
    fi
    # 检查consul是否加入集群
    if [[ $(consul info | awk '/known_servers =/ { print $NF }') -eq 0 ]]; then
        echo "consul 未加入任何集群，找不到server"
        return 1
    fi
    return 0
}

do_check() {
   local item=$1
   local step_file=$HOME/.bk_node_check

   if grep -qw "$item" "$step_file"; then
        echo "<<$item>> has been checked successfully... SKIP"
   else
        echo -n "start <<$item>> ... "
        message=$($item)
        if [ $? -eq 0 ]; then
            echo "[OK]"
            echo "$item" >> $step_file
        else
            echo "[FAILED]"
            echo -e "\t$message"
            exit 1
        fi
   fi
}

if [[ -z $BK_PRECHECK ]]; then
    BK_PRECHECK=(check_centos_7 check_selinux check_umask check_yum_repo
    check_http_proxy check_open_files_limit check_glibc_version check_firewalld)
fi

STEP_FILE=$HOME/.bk_node_check
# 根据参数设置标记文件
if [ "$1" = "-r" -o "$1" = "--rerun" ]; then
    > "$STEP_FILE"
else
   [ -e "$STEP_FILE" ] || touch "$STEP_FILE"
fi

for item in "${BK_PRECHECK[@]}"; do
   do_check "$item"
done