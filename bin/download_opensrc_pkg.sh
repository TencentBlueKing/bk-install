#!/usr/bin/env bash
# 目的：补全下载蓝鲸依赖的开源组件包

DOWNLOAD_PKG_TYPE=all
DOWNLOAD_DIR=$(pwd)

TMP_FILE=$(mktemp)
trap 'rm -f $TMP_FILE' EXIT

declare -r ZOOKEEPER_VER='3.4.14'
declare -r CONSUL_VER="1.7.1"
declare -r CONSUL_TEMPLATE_VER="0.25.1"
declare -r REDIS_VER="5.0.8"

declare -r INFLUXDB_VER="1.7.10"
declare -r MONGODB_VER="4.2.3"
declare -r ZERO_DEP_ERLANG_VER="21.3.8.14"
declare -r RABBITMQ_VER="3.8.3"
declare -r ELASTICSEARCH_VER='7.6.1'
declare -r MYSQL_VER="5.7.29"

cat <<EOF > "${TMP_FILE}"
# rpm
https://dl.influxdata.com/influxdb/releases/influxdb-${INFLUXDB_VER}.x86_64.rpm

http://mirrors.tencent.com/mongodb/yum/el7-4.2/RPMS/mongodb-org-${MONGODB_VER}-1.el7.x86_64.rpm
http://mirrors.tencent.com/mongodb/yum/el7-4.2/RPMS/mongodb-org-mongos-${MONGODB_VER}-1.el7.x86_64.rpm
http://mirrors.tencent.com/mongodb/yum/el7-4.2/RPMS/mongodb-org-server-${MONGODB_VER}-1.el7.x86_64.rpm
http://mirrors.tencent.com/mongodb/yum/el7-4.2/RPMS/mongodb-org-shell-${MONGODB_VER}-1.el7.x86_64.rpm
http://mirrors.tencent.com/mongodb/yum/el7-4.2/RPMS/mongodb-org-tools-${MONGODB_VER}-1.el7.x86_64.rpm

http://mirrors.tencent.com/mysql/yum/mysql-5.7-community-el7-x86_64/mysql-community-client-${MYSQL_VER}-1.el7.x86_64.rpm
http://mirrors.tencent.com/mysql/yum/mysql-5.7-community-el7-x86_64/mysql-community-common-${MYSQL_VER}-1.el7.x86_64.rpm
http://mirrors.tencent.com/mysql/yum/mysql-5.7-community-el7-x86_64/mysql-community-devel-${MYSQL_VER}-1.el7.x86_64.rpm
http://mirrors.tencent.com/mysql/yum/mysql-5.7-community-el7-x86_64/mysql-community-libs-${MYSQL_VER}-1.el7.x86_64.rpm
http://mirrors.tencent.com/mysql/yum/mysql-5.7-community-el7-x86_64/mysql-community-libs-compat-${MYSQL_VER}-1.el7.x86_64.rpm
http://mirrors.tencent.com/mysql/yum/mysql-5.7-community-el7-x86_64/mysql-community-server-${MYSQL_VER}-1.el7.x86_64.rpm

https://github.com/rabbitmq/erlang-rpm/releases/download/v${ZERO_DEP_ERLANG_VER}/erlang-${ZERO_DEP_ERLANG_VER}-1.el7.x86_64.rpm
https://github.com/rabbitmq/rabbitmq-server/releases/download/v${RABBITMQ_VER}/rabbitmq-server-${RABBITMQ_VER}-1.el7.noarch.rpm
https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELASTICSEARCH_VER}-x86_64.rpm

https://mirrors.tencent.com/docker-ce/linux/centos/7/x86_64/stable/Packages/docker-ce-18.09.9-3.el7.x86_64.rpm
https://mirrors.tencent.com/docker-ce/linux/centos/7/x86_64/stable/Packages/docker-ce-cli-18.09.9-3.el7.x86_64.rpm
https://mirrors.tencent.com/docker-ce/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.13-3.2.el7.x86_64.rpm
https://mirrors.tencent.com/docker-ce/linux/centos/7/x86_64/stable/Packages/docker-ce-selinux-17.03.3.ce-1.el7.noarch.rpm

# pkgs
https://releases.hashicorp.com/consul/${CONSUL_VER}/consul_${CONSUL_VER}_linux_amd64.zip
https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VER}/consul-template_${CONSUL_TEMPLATE_VER}_linux_amd64.tgz
http://download.redis.io/releases/redis-${REDIS_VER}.tar.gz
#http://mirrors.tencent.com/mysql/downloads/MySQL-5.7/mysql-${MYSQL_VER}-linux-glibc2.12-x86_64.tar.gz
https://downloads.apache.org/zookeeper/zookeeper-${ZOOKEEPER_VER}/zookeeper-${ZOOKEEPER_VER}.tar.gz
EOF

if [[ $DOWNLOAD_PKG_TYPE = rpm ]]; then
    sed -i '/rpm$/d' "$TMP_FILE"
fi 

cd "$DOWNLOAD_DIR" && \
while read -r url; do
curl -C - -sLO --connect-timeout 2 "$url"
done < <(sed -r '/^#/d; /^\s*$/d' "$TMP_FILE")