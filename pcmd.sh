#!/usr/bin/env bash
# 封装pssh，读取环境变量，执行命令

# 版本信息
VERSION=v1

# 加载环境变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
source ${SELF_DIR}/load_env.sh

TIMEOUT=7200
PAR=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [-m all|-H ip1,ip2] 'echo yes'
            [ -h --help -?  查看帮助 ]
            [ -m --module      [可选] 根据模块执行封装命令 ]
            [ -p --PAR         [可选] 允许最大并行线程数, 默认为所有机器并行执行]
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
        -p | --par )
            shift
            PAR=$1
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
# Usage: options=("one" "two" "three"); inputChoice "Choose:" 1 "${options[@]}"; choice=$?; echo "${options[$choice]}"
function inputChoice() {
    echo "${1}"; shift
    echo "$(tput dim)""- Change option: [up/down], Select: [ENTER]" "$(tput sgr0)"
    local selected="${1}"; shift

    ESC=$(echo -e "\033")
    cursor_blink_on()  { tput cnorm; }
    cursor_blink_off() { tput civis; }
    cursor_to()        { tput cup $(($1-1)); }
    print_option()     { echo "$(tput sgr0)" "$1" "$(tput sgr0)"; }
    print_selected()   { echo "$(tput rev)" "$1" "$(tput sgr0)"; }
    get_cursor_row()   { IFS=';' read -rsdR -p $'\E[6n' ROW COL; echo "${ROW#*[}"; }
    key_input()        { read -rs -n3 key 2>/dev/null >&2; [[ $key = ${ESC}[A ]] && echo up; [[ $key = ${ESC}[B ]] && echo down; [[ $key = "" ]] && echo enter; }

    for opt; do echo; done

    local lastrow
    lastrow=$(get_cursor_row)
    local startrow=$((lastrow - $#))
    trap "cursor_blink_on; echo; echo; exit" 2
    cursor_blink_off

    : selected:=0

    while true; do
        local idx=0
        for opt; do
            cursor_to $((startrow + idx))
            if [ ${idx} -eq "${selected}" ]; then
                print_selected "${opt}"
            else
                print_option "${opt}"
            fi
            ((idx++))
        done

        case $(key_input) in
            enter) break;;
            up)    ((selected--)); [ "${selected}" -lt 0 ] && selected=$(($# - 1));;
            down)  ((selected++)); [ "${selected}" -ge $# ] && selected=0;;
        esac
    done

    cursor_to "${lastrow}"
    cursor_blink_on
    echo

    return "${selected}"
}

if [ -z "$PAR" ]; then
    PARALLEL=""
else
    PARALLEL="-p $PAR"
fi

if ! [ -z "${module}" ];then
        if [ "$module" == "ALL" -o "$module" == "all" ]; then
        arrayname=ALL_IP
    else
        arrayname=BK_${module^^}_IP
    fi
    tmp=${arrayname}[@]
    # 封装pssh，并在登录后先加载目标机器上的load_env.sh
    pssh $PARALLEL -t "$TIMEOUT" -h <(printf "%s\n" "${!tmp}") -i -x "-T" -I <<EOF
source ${SELF_DIR}/load_env.sh
${COMM[@]}
EOF
else
    # 去除行尾逗号,兼容printf传入格式
    HOST_STRING=${HOST_STRING%,}
    tmp=( ${HOST_STRING//,/ } )
    # 封装pssh，并在登录后先加载目标机器上的load_env.sh
    pssh $PARALLEL -t "$TIMEOUT" -h <(printf "%s\n" "${tmp[@]}") -i -x "-T" -I <<EOF
source ${SELF_DIR}/load_env.sh
${COMM[@]}
EOF
fi
