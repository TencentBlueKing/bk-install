#!/usr/bin/env bash
# install_docker_for_paasagent.sh ：安装，配置docker
set -e

SELF_DIR="$(dirname "$(readlink -f "$0")")"

source ${SELF_DIR}/../load_env.sh

if ! rpm -q install docker-ce-18.09.9;then
    yum install docker-ce-18.09.9 -y
fi
# TODO: 需要自定义下daemon.json(参考dockerctl的start_docker()函数)
[[ -d /etc/docker ]] || mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
    "data-root": "$BK_HOME/public/docker",
    "exec-opts": ["native.cgroupdriver=cgroupfs"],
    "bridge": "none", 
    "iptables": false, 
    "ip-forward": true,
    "live-restore": true, 
    "log-level": "info",
    "log-driver": "json-file", 
    "log-opts": {
        "max-size": "501m",
        "max-file":"5"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ]
}
EOF

mkdir -p $BK_HOME/public/docker
systemctl enable --now docker

case $@ in
    paas_agent)
        # 为了让blueking身份运行的paasagent也能运行docker cli命令。
        usermod -G docker blueking

        docker load < ${BK_PKG_SRC_PATH}/image/python27e_1.0.tar
        docker load < ${BK_PKG_SRC_PATH}/image/python36e_1.0.tar 

        # 同步工具
        rsync -avz ${BK_PKG_SRC_PATH}/image/runtool /usr/bin/
        chmod +x  /usr/bin/runtool
        ;;
    *) : ;;
esac