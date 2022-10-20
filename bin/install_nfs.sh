#!/usr/bin/env bash
# 安装并配置蓝鲸的 nfs server
# 参考文档：https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/storage_administration_guide/ch-nfs
#          man 5 exports

# 安全模式
set -euo pipefail 

# 通用脚本框架变量
PROGRAM=$(basename "$0")
SELF_DIR=$(dirname "$(readlink -f "$0")")

BK_JOB_IP=
BK_PAAS_IP=
BK_APPO_IP=
BK_BKDATA_IP=
BK_NODEMAN_IP=

HOSTS_ENV=${SELF_DIR}/02-dynamic/hosts.env

# hosts.env是必须的，用来生成accesslist的ip
if ! [[ -s "$HOSTS_ENV" ]]; then
    echo "$HOSTS_ENV is empty"
    exit 1
else
    . "$HOSTS_ENV"
fi

# 默认值，可以通过传参覆盖
# nfs的存储目录
NFS_ROOT_DIR=/data/bkee/public/nfs 
# nfs 的uid和gid
NFS_UID=$(id -u blueking)
NFS_GID=$(id -g blueking)
MODULE=(paas job saas nodeman)  # 默认只安装基础的


usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -m, --module          [选填] "配置需要export的模块路径，生成/etc/exports.d/<模块名>.exports配置" ]
            [ -d, --nfs-root-dir    [选填] "模块在nfs server主机上的根路径，默认为$NFS_ROOT_DIR" ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo "$@"
}

error () {
    echo "$@" 1>&2
    usage_and_exit 1
}

fail () {
    echo "$@" 1>&2
    exit 1
}

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -m | --module)
            shift
            MODULE_STR="$1"
            ;;
        -d | --nfs-root-dir )
            shift
            NFS_ROOT_DIR=$1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -l | --log-dir )
            shift
            LOG_DIR=$1
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --version | -v | -V )
            version 
            exit 0
            ;;
        -*)
            error "不可识别的参数: $1"
            ;;
        *) 
            break
            ;;
    esac
    shift 
done 

declare -A NFS_MODULE_DIR=(
    ["job"]=$NFS_ROOT_DIR/job
    ["paas"]=$NFS_ROOT_DIR/open_paas
    ["saas"]=$NFS_ROOT_DIR/saas
    ["bkdata"]=$NFS_ROOT_DIR/bkdata
    ["nodeman"]=$NFS_ROOT_DIR/nodeman
)
declare -A NFS_MODULE_IPLIST=(
    ["job"]="${BK_JOB_IP[@]}"
    ["paas"]="${BK_PAAS_IP[@]}"
    ["saas"]="${BK_APPO_IP[@]}"
    ["bkdata"]="${BK_BKDATA_IP[@]}"
    ["nodeman"]="${BK_NODEMAN_IP[@]}"
)

if ! rpm -q nfs-utils >/dev/null 2>&1; then
    # 会自动安装rpcbind的依赖
    echo "install nfs-utils"
    yum -y install nfs-utils
    # 如果没启动，则启动，并设置开机启动
    # nfs会指向nfs-server.service,会自动启动依赖的service和target
fi

if ! systemctl is-active nfs &>/dev/null; then
    systemctl start nfs
    systemctl enable nfs
fi

# 创建nfs对应模块的目录
create_module_exports_dir () {
    local module=$1
    local module_dir=${NFS_MODULE_DIR[$module]}
    echo "创建模块目录($module_dir)"
    install -d -m 755 -o "$NFS_UID" -g "$NFS_GID" "$module_dir"
}

# 创建模块对应的配置文件，在/etc/exports.d/*.exports 为文件名
create_module_exports_conf () {
    local module=$1
    local module_dir=${NFS_MODULE_DIR[$module]}
    local exports_conf=/etc/exports.d/${module}.exports
    local perm="rw,all_squash,anonuid=$NFS_UID,anongid=$NFS_GID"
    local iplist=(${NFS_MODULE_IPLIST[$module]})
    echo ${NFS_MODULE_IPLIST[$module]}
    if [[ ${#iplist[@]} -gt 0 ]]; then
        echo "write $exports_conf"
        { 
            for ip in "${iplist[@]}"; do
                echo "$module_dir $ip($perm)"
            done
        } > "$exports_conf"
    else
        echo "$module iplist is empty, skip."
    fi
}

for m in "${MODULE[@]}"; do
    create_module_exports_dir "$m"
    create_module_exports_conf "$m"
done

# 加载配置
exportfs -ra