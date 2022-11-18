#!/usr/bin/env bash
# 封装pssh，读取环境变量，执行命令

# 版本信息
VERSION=v1

# 加载环境变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
source ${SELF_DIR}/load_env.sh

TIMEOUT=7200

usage () {
    cat <<EOF
用法: 
    $PROGRAM [-m all|-H ip1,ip2] 'echo yes'
            [ -h --help -?  查看帮助 ]
            [ -m --module      [可选] 根据模块执行封装命令 ]
            [ -H --host-string [可选] 根据以逗号分隔的ip列表执行封装命令 ]
            [ -v, --version    [可选] 查看脚本版本号 ]
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
# parse command line args
while (( $# > 0 )); do 
    case "$1" in
        -m | --module )
            shift
            module=$1
            ;;
        -H | --host-string )
            shift
            HOST_STRING=$1
            ;;
        -h | --help )
            usage_and_exit 1
            ;;
        -v | --version )
            version
            ;;
        -- ) shift; break;;  # 语法糖 ^_^
        *)   break  # 如果遇到其他情况, 则停止选项解析.
    esac
    shift 
done 
COMM=("$@")

# 参数校验
if [[ -o "${module}" && -o "${HOST_STRING}" ]];then
    error "-m, -H 不可同时使用"
fi

if [[ -z "${module}" && -z "${HOST_STRING}" ]];then
    error "-m, -H 不可同时为空"
fi


if ! [ -z "${module}" ];then
    if [ $module == "ALL" -o $module == "all" ]; then
        arrayname=ALL_IP
    else
        arrayname=BK_${module^^}_IP
    fi
    tmp=${arrayname}[@]
    # 封装pssh，并在登录后先加载目标机器上的load_env.sh
    pssh -t "$TIMEOUT" -h <(printf "%s\n" "${!tmp}") -i -x "-T" -I <<EOF
source ${SELF_DIR}/load_env.sh
${COMM[@]}
EOF
else
    # 去除行尾逗号,兼容printf传入格式
    HOST_STRING=${HOST_STRING%,}
    tmp=( ${HOST_STRING//,/ } )
    # 封装pssh，并在登录后先加载目标机器上的load_env.sh
    pssh -t "$TIMEOUT" -h <(printf "%s\n" "${tmp[@]}") -i -x "-T" -I <<EOF
source ${SELF_DIR}/load_env.sh
${COMM[@]}
EOF
fi
