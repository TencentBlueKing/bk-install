#!/usr/bin/env bash
# 用途：将蓝鲸的一些基础配置写入到consul的kv存储，默认的prefix是bkcfg/
# 脚本调用时，假设已经配置好了consul命令行所需要的环境变量，比如ca证书，地址，端口等。
# 写入的值也是假设通过环境变量传入了，脚本只维护环境变量的和consul key的映射关系。

SELF_DIR=$(dirname "$(readlink -f "$0")")
BK_ENV_FILE=${BK_ENV_FILE:-$SELF_DIR/load_env.sh}
PREFIX=bkcfg
DRY_RUN=
CONFIG_FILE=()

usage () {
    cat <<EOF
用法: 
    $PROGRAM -p bkcfg -e load_env.sh -f bk_kv.conf -f bk_bcs_kv.conf ...

            [ -p, --prefix      [可选] "指定存储在consul的kv的root目录，默认为bkcfg/，配置文件中读取的第一列key都是相对于prefix的" ]
            [ -e, --env-file    [可选] "指定加载的蓝鲸环境变量文件，将会覆盖\$BK_ENV_FILE的值，优先级最高" ]
            [ -f, --file        [必选] "脚本的配置文件，可多次指定，先指定的先处理" ]
            [ -n, --dry-run     [可选] "打印出将会运行的consul kv命令，并不实际执行" ]

            [ -h, --help        [可选] 查看脚本帮助 ]
            [ -v, --version     [可选] 查看脚本版本号 ]

    配置文件格式为，第一列consul中存储的kv路径（相对于prefix，[a-z]开头），第二列为环境变量名，如果@开头表示这是个数组。
    #开头表示注释行，空行忽略，例如：
    ----bk_kv.conf
    # 蓝鲸安装路径
    common/bk_home BK_HOME
    # rabbitmq的ip地址列表
    hosts/rabbitmq @RABBITMQ_IP

    ----
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

make_json_array () {
    local e 
    if [[ $# -eq 0 ]]; then
        echo "[]"
        return 0
    fi
    printf '%s\n' "$@" | jq -R . |  jq -cs .
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -n | --dry-run )
            DRY_RUN=1
            ;;
        -p | --prefix )
            shift
            PREFIX=$1
            ;;
        -e | --env-file )
            shift
            BK_ENV_FILE="$1"
            ;;
        -f | --config-file)
            shift
            CONFIG_FILE+=("$1")
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

if ! command -v jq &>/dev/null; then
    warning "jq command not found."
fi

# 加载 BK_ENV_FILE 这个变量指向的文件里的变量为环境变量，作用范围是本脚本。
#if [[ -r "$BK_ENV_FILE" ]]; then
#    set -o allexport
#    source "$BK_ENV_FILE"
#else
#    warning "$BK_ENV_FILE 文件不可读"
#fi
#set +o allexport

# 直接读入final里的所有env
if [[ -d ${SELF_DIR}/04-final ]]; then
    warning "不存在${SELF_DIR}/04-final文件夹"
fi

if (( ${#CONFIG_FILE[@]} == 0 )); then
    error "未指定任何配置文件"
fi

for f in "${CONFIG_FILE[@]}"; do
    [[ -r "$f" ]] || warning "$f 不可读"
done

if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

set -o nullglob
set -o allexport
for e in "${SELF_DIR}"/04-final/*.env; do
    source "$e"
done
set +o allexport
set +o nullglob

for f in "${CONFIG_FILE[@]}"; do
    while read -r k e; do
        if [[ $e = @* ]]; then
            # array 
            e=${e#@}
            tmp=${e}[@]
            if [[ $DRY_RUN -eq 1 ]];then
                echo consul kv put "$PREFIX/$k" "$(make_json_array "${!tmp}")"
            else
                consul kv put "$PREFIX/$k" "$(make_json_array "${!tmp}")" || ((EXITCODE++))
            fi
        else
            # string 
            v=$(printenv "$e")
            if [[ $DRY_RUN -eq 1 ]];then
                echo consul kv put "$PREFIX/$k" "$v"
            else
                consul kv put "$PREFIX/$k" "$v" || ((EXITCODE++))
            fi
        fi
    done < <(awk '/^[[:space:]]*[a-z]/' "$f")
done

exit "$EXITCODE"