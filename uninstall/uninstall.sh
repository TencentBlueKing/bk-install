#!/usr/bin/env bash
# Desc: uninstall blueking suit on single host
# shellcheck disable=SC1090

export LC_ALL=C LANG=C
SELF_DIR=$(dirname "$(readlink -f "$0")")

CTRL_DIR=${SELF_DIR}

# load common functions & variables
if [[ -r $CTRL_DIR/utils.fc ]]; then
    source "$CTRL_DIR/utils.fc"
else
    echo "you should cp uninstall.sh to /data/install, not directly invoked under $SELF_DIR/"
    exit 1
fi

# include some useful functions
clean_crontab () {
    log "clean crontab settings"
    crontab <( crontab -l | grep -v "/watch.rc;" \
                          | grep -v "/process_watch " \
                          | grep -v "$BK_HOME" \
                          | grep -v "/usr/local/gse/" )
    return 0
}

# check user
[[ $USER = "root" ]] || fail "please run $0 as root."

# confirm
echo "this script will kill all processes related to Blueking Suit on $LAN_IP"
echo "and following directories, make sure you have backups before confirm"
echo "- $BK_PKG_SRC_PATH"
echo "- $BK_HOME"
echo "- $CTRL_DIR"
echo "if you really want to uninstall, please input yes to continue"
read -rp "yes/no? " reply
if [[ "$reply" != "yes" ]]; then
    echo "Abort"
    exit 1
fi

step "clear crontab entry contains $BK_HOME"
clean_crontab

step "stop all bk-*.service"
( cd /usr/lib/systemd/system/ && systemctl disable --now bk-*.service )
( cd /usr/lib/systemd/system/ && systemctl disable --now bk-*.target blueking.target )
step "delete all bk-*.service unit files"
rm -fv /usr/lib/systemd/system/bk-*.service /usr/lib/systemd/system/bk-*.target 

step "stop third-party service"
declare -a THIRD_PARTY_SVC=(
    consul
    consul-template
    mysql@*
    redis@*
    redis.target
    openresty
    rabbitmq-server
    zookeeper
    mongod
    kafka
    elasticsearch
    influxdb
    beanstalkd
)
systemctl disable --now "${THIRD_PARTY_SVC[@]}" 2>&1 | grep -v 'not loaded'
systemctl disable --now redis@default.service
systemctl disable --now mysql@default.service

# if docker running, stop all,delete all,first
step "clear all docker container"
if mount | grep -q public/paas_agent/docker 2>/dev/null; then
    docker kill $(docker ps -q)
    docker rm $(docker ps -a -q)
    docker rmi $(docker images -q)
    pkill -9 dockerd containerd
    mount_point=$(mount | grep -Eo "$BK_HOME/public/paas_agent/docker/[a-z]+")
    [[ $mount_point =~ docker ]] && umount $mount_point
fi

# if docker start by systemd
systemctl stop docker
mount_product_point=$(mount | grep -E "$BK_HOME/public/docker/[a-z0-9]+" | awk '{print $3}')
[[ $mount_product_point =~ docker ]] && umount $mount_product_point

# STOP all process running under $BK_HOME
step "kill all process running under $BK_HOME"
if [[ -e "$BK_HOME" && "$BK_HOME" != "/" ]]; then
    stat -c %N /proc/*/fd/* 2>&1 \
        | awk -v p="$BK_HOME" -v c="$CTRL_DIR" '$0 ~ p && $0 !~ c {print $1}' \
        | awk -F/ '{print $3}' | sort -u | xargs kill -9 
else
    echo "$BK_HOME is not exist or equal \"/\""
    exit 1
fi

# STOP all processes left
pkill -9 gunicorn
pkill -9 influxd 

# REMOVE rsyslog config
rm -fv /etc/rsyslog.d/influxdb.conf /etc/rsyslog.d/bk-cmdb.conf && systemctl restart rsyslog

# uninstall bk python and rpm
step "remove blueking python and yum installed under /opt/"
rm -rf /opt/{py{27,27_e,36,36_e},yum}

# uninstall rpm installed 
step "remove third-party rpm"
## cd /opt/yum && rpm -qp --queryformat '%{NAME} ' *.rpm 2>/dev/null
THIRD_PARTY_RPM=(consul consul-template containerd.io container-selinux 
docker-ce docker-ce-cli docker-ce-selinux elasticsearch erlang influxdb 
kafka mongodb-org mongodb-org-mongos mongodb-org-server mongodb-org-shell
mongodb-org-tools mysql-community-client mysql-community-common mysql-community-devel 
mysql-community-libs mysql-community-libs-compat mysql-community-server openresty
prometheus2 rabbitmq-server redis zookeeper zookeepercli beanstalkd)

yum -y remove "${THIRD_PARTY_RPM[@]}"

# uninstall nfs service if exists
if mount | grep -q "$BK_HOME"/public/nfs ; then
    umount -f -l "$BK_HOME"/open_paas/paas/media
    umount -f -l "$BK_HOME"/public/job
    umount -f -l "$BK_HOME"/public/bknodeman
fi

if ps -C nfsd &>/dev/null; then
    step "remove nfs service"
    systemctl stop nfs rpcbind rpc-statd
    systemctl disable nfs rpcbind rpc-statd
    sed -i "/public\/nfs/d" /etc/exports
fi

step "remove $HOME/.bkrc; remove /etc/resolv.conf entry; remove other left over files"
sed -i '/127.0.0.1/d' /etc/resolv.conf
sed -i '/node.consul/d' /etc/resolv.conf
rm -fv ~/.bkrc ~/.bk_controller_check ~/.erlang.cookie /etc/rc.d/bkrc.local 
rm -rf ~/.virtualenvs ~/.local/share/virtualenv 
rm -rvf /var/lib/{consul,redis,zookeeper,rabbitmq,elasticsearch}
rm -rvf /var/log/{consul,redis,zookeeper,kafka} /var/log/mysqld.log

if ps -C agentWorker &>/dev/null; then
    step "remove gse_agent"
    for p in gseMaster agentWorker basereport exceptionbeat bkmetricbeat processbeat unifytlogc; do 
        pkill -9 $p 
    done
    rm -rf /usr/local/gse /var/log/gse /var/run/gse /var/lib/gse
fi

step "remove $BK_HOME $BK_PKG_SRC_PATH $CTRL_DIR"
chattr -i "$CTRL_DIR"/.migrate/* "$HOME"/.migrate/* "$HOME"/.tag/* 2>/dev/null
[[ -e $BK_PKG_SRC_PATH ]] && rm -rf ${BK_PKG_SRC_PATH}
[[ -e $BK_HOME ]] && rm -rf "${BK_HOME}"
[[ -e $CTRL_DIR ]] && rm -rf "${CTRL_DIR}"
[[ -e $HOME/.migrate ]] && rm -rf "$HOME"/.migrate
[[ -e $HOME/.tag ]] && rm -rf "$HOME"/.tag
[[ -e $HOME/.mylogin.cnf ]] && rm -f "$HOME"/.mylogin.cnf

step "Run(lsof +L1) to see if any process exists"
if lsof +L1 | grep -E "$BK_HOME|/var/log/gse"; then
    echo "if you really want to kill these left over processes, please input yes to continue"
    read -rp "yes/no? " reply
    if [[ "$reply" != "yes" ]]; then
        echo "Abort"
        exit 1
    else
    lsof +L1 | grep -E "$BK_HOME|/var/log/gse" \
        | awk '$1 != "lsof" { print $2 }' | sort -u \
        | xargs kill -9 
    fi
fi

# remove system config files
[[ -d /etc/blueking ]] && rm -rf /etc/blueking
rm -fv /etc/sysconfig/bk-* /etc/tmpfiles.d/{bkmonitorv3,gse,usermgr,bklog,bknodeman,cmdb,open_paas,bkmonitorv3,fta}.conf
rm -fv /etc/logrotate.d/bk-cmdb /etc/security/limits.d/bk-nofile.conf 
rm -fv /etc/yum.repos.d/Blueking.repo
rm -fv /usr/local/openresty/nginx/conf/conf.d/*
rm -rfv /etc/consul.d /etc/elasticsearch /etc/kafka/ /etc/zookeeper \
    /etc/redis /etc/mysql /etc/consul-template /etc/docker /etc/rabbitmq \
    /etc/mongod.* 

# 删除 /tmp下一些无属主的文件
find /tmp -maxdepth 2 -nouser -o -nogroup | xargs rm -rf 

# 清理用户
for u in nginx rabbitmq epmd es cmdb apps beanstalkd influxdb etcd nfs blueking logstash consul redis mysql kafka zookeeper mongod; do
    userdel --remove --force $u 2>/dev/null
done

# 清理单独安装的二进制
[[ -f /usr/bin/runtool ]] && rm -f /usr/bin/runtool 

# reset failed systemd units
systemctl reset-failed