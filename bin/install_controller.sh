#!/usr/bin/env bash
# 用途：生成中控机需要的，以及后续要分发到其他机器上的资源以及配置文件。

# 安全模式
set -euo pipefail

SELF_DIR="$(dirname "$(readlink -f "$0")")"

# 安装批量工具pssh parallel
if ! rpm -q pssh parallel mysql-community-client zip unzip rsync gawk curl lsof tar sed iproute uuid psmisc wget at > /dev/null 2>&1; then
    yum -y install pssh parallel mysql-community-client zip unzip rsync gawk curl lsof tar sed iproute uuid psmisc wget at 
fi

if ! rpm -q  rsync jq expect uuid bash-completion lsof openssl-devel readline-devel libcurl-devel libxml2-devel glibc-devel \ 
                                zlib-devel iproute sysvinit-tools procps-ng bind-utils > /dev/null 2>&1;then
    yum install -y rsync jq expect uuid bash-completion lsof openssl-devel readline-devel libcurl-devel libxml2-devel glibc-devel \
                                zlib-devel iproute sysvinit-tools procps-ng bind-utils 
fi

# 配置parallel免声明
if ! [[ -r $HOME/.parallel/will-cite ]]; then
    mkdir "$HOME"/.parallel
    touch "$HOME"/.parallel/will-cite
fi