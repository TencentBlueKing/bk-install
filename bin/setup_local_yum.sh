#!/usr/bin/env bash
# 用途：离线安装yum依赖包,适用于内网环境存在yum源的情况

set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
REPO_CONFIG_PATH=/etc/yum.repos.d/Blueking.repo
AUTO_CONFIG=0

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -l, --local-url   [必选] "指定本地yum源地址，格式：http://xxxxxxx" ]
            [ -a, --auto-config [可选] "是否配置$REPO_CONFIG_PATH" ]
            [ -v, --version     [可选] 查看脚本版本号 ]
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

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

version () {
    echo "$PROGRAM version $VERSION"
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -l | --local-url )
            shift
            YUM_URL=${1-"3"}
            ;;
        -a | --auto-config )
            AUTO_CONFIG=1
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

# 参数合法性有效性校验，这些可以使用通用函数校验。
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

set +u 
if [[ -z $YUM_URL ]]; then
    log "请输入本地yum仓库地址"
    exit "$EXITCODE"
fi

if ! [[ -d "${REPO_CONFIG_PATH%/*}" ]];then
    log "不存在 ${REPO_CONFIG_PATH%/*} 目录"
    exit "$EXITCODE"
fi


# 写入配置，该路径的优先级>/etc/yum.repos.d
if [[ $AUTO_CONFIG -eq 1 ]]; then
    log "写入yum配置文件：$REPO_CONFIG_PATH"
    cat <<EOF | tee "$REPO_CONFIG_PATH"
[bk-custom]
name=Blueking
baseurl=$YUM_URL
enabled=1   
gpgcheck=0  
EOF
fi

# 生成元数据缓存 并校验是否存在consul
yum makecache
if yum info consul &>/dev/null; then
    echo "setup local yum successful"
else
    echo "setup local yum failed"
    exit 1
fi
