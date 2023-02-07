#!/usr/bin/env bash
# 用途：从gse后台包中，合并证书文件，和插件小包，打出gse_client包，供节点管理使用。
# shellcheck disable=SC1090,SC2231
# 安全模式
set -euo pipefail 

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
CERT_PATH=/data/bkee/cert       # 证书所在目录
GSE_TGZ_PATH=                   # gse压缩包路径
GSE_OUTPUT_DIR=/tmp/gse         # 打包归档的目录
ENV_FILE=                       # 渲染模板的环境变量文件
TAG=                            # 是否需要双Agent来区分路径用
BK_GSE_AGENT_HOME=/usr/local/gse   # gse agent的默认安装家目录
NEED_RENDER=                    # 是否需要渲染agent配置，默认不渲染

# plugins pack with gse client/proxy 
BASE_PLUGINS=(
    exceptionbeat gsecmdline bkmonitorbeat bkunifylogbeat bk-collector
)

# error exit handler
err_trap_handler () {
    MYSELF="$0"
    LASTLINE="$1"
    LASTERR="$2"
    echo "${MYSELF}: line ${LASTLINE} with exit code ${LASTERR}" >&2
}
trap 'err_trap_handler ${LINENO} $?' ERR

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -c, --cert-path   [必选] "GSE证书所在目录，默认为/data/bkee/cert" ]
            [ -f, --gse-tgz     [必选] "指定gse压缩包的路径，适用于尚未解压gse包时从中抽取gse客户端打包的场景" ]
            [ -p, --plugin-dir  [可选] "指定插件压缩小包所在目录" ]
            [ -o, --output-dir  [可选] "指定打包好的文件放到哪个目录下，默认为/tmp/gse下" ]
            [ -t, --tag         [可选] "指定该agent的标识，双Agent安装时用来修改路径相关避免冲突" ]
            [ -e, --env-file    [可选] "指定从该文件读取环境变量来渲染配置文件模板。" 
            [ -r, --render      [可选] "是否渲染agent的配置文件" 

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

# modify default config entry
tweak_tag () {
    local tag=$1
    shift 1
    sed -r -i "
        s|/var/log/gse|/var/log/gse_${tag}|g;
        s|/var/lib/gse|/var/lib/gse_${tag}|g;
        s|/var/run/gse|/var/run/gse_${tag}|g;
        /C:[/\]/ s,gse,gse_${tag},1;
        s|ipc.state.report|ipc.state.report.${tag}|g;
    "  "$@"
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -c | --cert-path )
            shift
            CERT_PATH=$1
            ;;
        -e | --env-file )
            shift
            ENV_FILE=$1
            ;;
        -t | --tag )
            shift
            TAG=$1
            ;;
        -f | --gse-tgz )
            shift
            GSE_TGZ_PATH=$1
            ;;
        -p | --plugin-dir )
            shift
            PLUGIN_TGZ_DIR=$1
            ;;
        -o | --output-dir )
            shift
            GSE_OUTPUT_DIR=$1
            ;;
        -r | --render)
            NEED_RENDER=1
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
    shift $(( $# == 0 ? 0 : 1 ))
done 

# check params
if ! [[ -r $CERT_PATH/gse_agent.crt ]]; then
    warning "$CERT_PATH/gse_agent.crt证书文件不存在，请检查路径"
fi

if ! [[ -f "$GSE_TGZ_PATH" ]]; then
    warning "$GSE_TGZ_PATH 文件不存在"
fi
if ! [[ -d "$PLUGIN_TGZ_DIR" ]]; then
    warning "$PLUGIN_TGZ_DIR 目录不存在"
fi
PLUGIN_TGZ=()
shopt -s nullglob
for p in "${BASE_PLUGINS[@]}"; do
    files=( $(printf "%s\n" "$PLUGIN_TGZ_DIR"/"$p"-*.tgz | sort -rV) )
    if (( ${#files[@]} > 0 )); then
        PLUGIN_TGZ+=(${files[0]})
    else
        warning "$p 插件包不存在任何版本"
    fi
done
shopt -u nullglob

if (( ${#PLUGIN_TGZ[@]} != ${#BASE_PLUGINS[@]} )); then
    warning "指定的$PLUGIN_TGZ_DIR中的插件包数量不对，请确认包含${BASE_PLUGINS[*]}这些包"
fi

PLUGIN_SCRIPTS_FILES=( $(cd $PLUGIN_TGZ_DIR && printf "%s\n" pluginscripts-*.tgz | sort -rV) )
PLUGIN_SCRIPTS=${PLUGIN_SCRIPTS_FILES[0]}
if ! [[ -f $PLUGIN_TGZ_DIR/$PLUGIN_SCRIPTS ]]; then
    warning "不存在 $PLUGIN_TGZ_DIR/$PLUGIN_SCRIPTS 包"
fi

# 需要渲染配置文件，才需要ENV_FILE
if [[ $NEED_RENDER -eq 1 ]]; then
    if [[ -n "$ENV_FILE" ]] && [[ ! -r "$ENV_FILE" ]]; then
        warning "指定的$ENV_FILE文件不可读取"
    fi
fi

if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# start packing
tmpdir=$(mktemp -d /tmp/pack_gse_client.XXXX)
trap 'rm -rf $tmpdir' EXIT

echo "extracting gse package to $tmpdir"
tar --wildcards -xf "$GSE_TGZ_PATH" -C "$tmpdir/" "gse/agent*" gse/proxy gse/support-files
echo "extracting plugin package to $tmpdir"
for f in "${PLUGIN_TGZ[@]}"; do
    tar -xf "$f" -C "$tmpdir/"
done
echo "extracting plugin scripts to $tmpdir"
tar -xf "$PLUGIN_TGZ_DIR/$PLUGIN_SCRIPTS" -C "$tmpdir/"

# now we change to output dir
GSE_OUTPUT_DIR=${GSE_OUTPUT_DIR%/}  # strip end slash / 
[[ -d $GSE_OUTPUT_DIR ]] || mkdir -p "$GSE_OUTPUT_DIR"
cd "$GSE_OUTPUT_DIR" || { echo "change dir to $GSE_OUTPUT_DIR failed."; exit 2; }
rm -rf ./agent ./proxy ./plugins

# pack client
for os in linux windows aix6 aix7; do
    for arch in x86_64 x86 aarch64 powerpc; do
        m="${os}_${arch}"
        if [[ -e $tmpdir/gse/agent_$m ]]; then
            log "packing agent($m)"
            cp -a "$tmpdir/gse/agent_$m" agent
            cp -a "${CERT_PATH}"/{gseca.crt,gse_agent.crt,gse_agent.key} agent/cert/
            # 社区版证书没有cert_encrypt.key文件
            [[ -f "${CERT_PATH}"/cert_encrypt.key ]] && cp -a "${CERT_PATH}"/cert_encrypt.key agent/cert/

            # render agent/plugin config template if needed
            if [[ $NEED_RENDER -eq 1 ]]; then
                shopt -s nullglob
                set +e
                for f in ${tmpdir}/gse/support-files/templates/agent_${m}\#etc\#*; do
                    "${SELF_DIR}"/render_tpl -n -e "${ENV_FILE}" "$f" > "agent/etc/${f##*#}"
                done
                set -e
                shopt -u nullglob
            fi

            if [[ -n "$TAG" && $NEED_RENDER -eq 1 ]]; then
                # check to avoid nullglob
                agent_config=(agent/etc/*)
                if [[ -e ${agent_config[0]} ]]; then
                    tweak_tag "$TAG" agent/etc/*
                fi
            fi

            mkdir -p plugins/{bin,etc}

            if [[ -e "$tmpdir"/plugins_${m} ]]; then
                cp -a "$tmpdir"/plugins_${m}/*/bin/* plugins/bin/
                cp -a "$tmpdir"/plugins_${m}/pluginscripts/bin/* plugins/bin/ || true # 拷贝脚本
                cp -a "$tmpdir"/plugins_${m}/*/etc/* plugins/etc/
                rm -f plugins/etc/*.tpl

                if [[ $NEED_RENDER -eq 1 ]]; then
                    (
                        source "$ENV_FILE"
                        # config add tag if needed
                        if [[ -n "$TAG" ]]; then
                            sed -i "s|/usr/local/gse|$BK_GSE_AGENT_HOME|" plugins/etc/*
                            tweak_tag "$TAG" plugins/etc/*
                        fi
                    )
                fi
            else
                echo "there is no gse/plugins_$m directory"
            fi

            tar -czf gse_client-${os}-${arch}.tgz ./agent ./plugins \
                && tar -czf gse_client-${os}-${arch}_upgrade.tgz ./agent/bin \
                && rm -rf ./agent ./plugins \
                && echo "$GSE_OUTPUT_DIR/gse_client-${os}-${arch}.tgz DONE"
        else
            echo "there is no gse/agent_$m directory"
        fi

    done
done

# pack proxy
log "packing proxy"
cp -a "${tmpdir}/gse/proxy" proxy
mkdir -p plugins/{bin,etc}
cp -a "$tmpdir"/plugins_linux_x86_64/*/bin/* plugins/bin/
cp -a "$tmpdir"/plugins_linux_x86_64/pluginscripts/bin/* plugins/bin/ || true # 拷贝脚本
cp -a "$tmpdir"/plugins_linux_x86_64/*/etc/* plugins/etc/
rm -f plugins/etc/*.tpl
cp -a "${CERT_PATH}"/{gseca.crt,gse_agent.*,gse_server.*,gse_api_client*} proxy/cert/
# 社区版证书没有cert_encrypt.key文件
[[ -f "${CERT_PATH}"/cert_encrypt.key ]] && cp -a "${CERT_PATH}"/cert_encrypt.key proxy/cert/

# render agent/plugin config template
if [[ $NEED_RENDER -eq 1 ]]; then
    for f in ${tmpdir}/gse/support-files/templates/proxy\#etc\#*; do
        "${SELF_DIR}"/render_tpl -n -e "${ENV_FILE}" "$f" > "proxy/etc/${f##*#}"
    done
    ( 
        source "$ENV_FILE"
        # config add tag if needed
        if [[ -n "$TAG" ]]; then
            sed -i "s|/usr/local/gse|$BK_GSE_AGENT_HOME|" plugins/etc/*
            tweak_tag "$TAG" proxy/etc/* plugins/etc/*
        fi
    )
fi

tar -czf gse_proxy-linux-x86_64.tgz ./proxy ./plugins \
    && tar -czf gse_proxy-linux-x86_64_upgrade.tgz ./proxy/bin \
    && rm -rf ./proxy ./plugins \
    && echo "$GSE_OUTPUT_DIR/gse_proxy-linux-x86_64.tgz DONE"

# 保证任意用户可读
chmod 644 "$GSE_OUTPUT_DIR"/*.tgz 
