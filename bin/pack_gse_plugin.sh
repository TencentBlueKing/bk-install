#!/usr/bin/env bash
# 用途：从gse 插件大包，打出适合节点管理后台init的小包格式
# shellcheck disable=SC1090,SC2231
# 安全模式
set -euo pipefail 
shopt -s nullglob

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# 通用脚本框架变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
PLUGIN_TGZ_PATH=		# plugin的tgz文件路径
GSE_OUTPUT_DIR=/tmp/gse         # 打包归档的目录
ENV_FILE=                       # 渲染模板的环境变量文件
TAG=                            # 是否需要双Agent来区分路径用

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
            [ -p, --plugin-tgz  [可选] "指定gse_plugins的压缩包路径" ]
            [ -o, --output-dir  [可选] "指定打包好的文件放到哪个目录下，默认为/tmp/gse下" ]
            [ -t, --tag         [可选] "指定该agent的标识，双Agent安装时用来修改路径相关避免冲突" ]
            [ -e, --env-file    [可选] "指定从该文件读取环境变量来渲染配置文件模板。" 

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
    sed -i "
        s|/var/log/gse|/var/log/gse_${tag}|g;
        s|/var/lib/gse|/var/lib/gse_${tag}|g;
        s|/var/run/gse|/var/run/gse_${tag}|g;
        s|ipc.state.report|ipc.state.report.${tag}|g;
    "  "$@"
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -e | --env-file )
            shift
            ENV_FILE=$1
            ;;
        -t | --tag )
            shift
            TAG=$1
            ;;
        -p | --plugin-tgz )
            shift
            PLUGIN_TGZ_PATH=$1
            ;;
        -o | --output-dir )
            shift
            GSE_OUTPUT_DIR=$1
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

# check params
if ! [[ -f "$PLUGIN_TGZ_PATH" ]]; then
    warning "$PLUGIN_TGZ_PATH 文件不存在"
fi

if [[ -n "$ENV_FILE" ]] && [[ ! -r "$ENV_FILE" ]]; then
    warning "指定的$ENV_FILE文件不可读取"
fi

if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# start packing
tmpdir=$(mktemp -d /tmp/pack_gse_plugins.XXXXX)
trap 'rm -rf $tmpdir' EXIT

echo "extracting package to $tmpdir"
tar -xf "$PLUGIN_TGZ_PATH" -C "$tmpdir/"

# after extracting tmpdir becomes + gse/
tmpdir=${tmpdir}/gse

# now we change to output dir
GSE_OUTPUT_DIR=${GSE_OUTPUT_DIR%/}  # strip end slash / 
[[ -d $GSE_OUTPUT_DIR ]] || mkdir -p "$GSE_OUTPUT_DIR"
( cd $GSE_OUTPUT_DIR && rm -rf *.tgz )
#cd "$GSE_OUTPUT_DIR" || { echo "change dir to $GSE_OUTPUT_DIR failed."; exit 2; }
cd "$tmpdir" || { echo "change dir to $tmpdir failed."; exit 2; }


get_single_plugin_desc_info () {
    local yaml=$1
    awk -v plugin=$2 '
      BEGIN{ regex="^- name: "plugin;}
      $0 ~ regex { print; flag=1; next }
      $0 ~ /^-/ { flag=0 } flag' $yaml \
    | sed -r 's/^-? *//'
}

get_single_plugin_control_info () {
    local os=$1
    local plugin=$2
    if [[ $os == "linux" ]]; then
        cat <<EOF
control:
  start: "./start.sh $plugin"
  stop: "./stop.sh $plugin"
  restart: "./restart.sh $plugin"
  reload: "./reload.sh $plugin"
  version: "./$plugin -v"
EOF
    elif [[ $os == "windows" ]]; then
        cat <<EOF
control:
  start: "start.bat $plugin"
  stop: "stop.bat $plugin"
  restart: "restart.bat $plugin"
  version: "${plugin}.exe -v"
EOF
    fi
}

####### 修改插件默认的配置文件路径
# 通用修改
if [[ -n "$TAG" ]]; then
    # 修改windows安装路径
    sed -i -r "/C:[/\]/ s,gse,gse_$TAG,1" "$tmpdir"/support-files/templates/plugin*
    tweak_tag "$TAG" $p/$m/$p/etc/*
fi

# 增加hostid配置
# basereport
sed -i '/host_id_path:/d' "$tmpdir"/support-files/templates/*basereport*
sed -i '/path.pid:/a basereport.host_id_path: /var/lib/gse_cloud/host/hostid' "$tmpdir"/support-files/templates/plugins_*linux*basereport*
sed -i "/path.pid:/a basereport.host_id_path: 'C:\\\gse_cloud\\\data\\\host\\\hostid'" "$tmpdir"/support-files/templates/plugins_*windows*basereport*

# bkmonitorbeat
sed -i '/host_id_path:/d' "$tmpdir"/support-files/templates/*bkmonitorbeat*
sed -i '/^bkmonitorbeat:/a \ \ host_id_path: /var/lib/gse_cloud/host/hostid' "$tmpdir"/support-files/templates/plugins_*linux*bkmonitorbeat*
sed -i "/^bkmonitorbeat:/a \ \ host_id_path: 'C:\\\gse_cloud\\\data\\\host\\\hostid'" "$tmpdir"/support-files/templates/plugins_*windows*bkmonitorbeat*

# processbeat
sed -i '/hostfilepath/d' "$tmpdir"/support-files/templates/*processbeat*
sed -i '/path.pid:/a processbeat.hostfilepath: /var/lib/gse_cloud/host/hostid' "$tmpdir"/support-files/templates/plugins_*linux*processbeat*
sed -i "/path.pid:/a processbeat.hostfilepath: 'C:\\\gse_cloud\\\data\\\host\\\hostid'" "$tmpdir"/support-files/templates/plugins_*windows*processbeat*

# pack plugins
plugin_ver=$(cat plugins_linux_x86_64/project.yaml | awk '/^- name|version/ { print $NF}' | xargs -n 2)
plugins=( $(cut -d' ' -f1 <<<"$plugin_ver") )
echo "There are ${#plugins[@]} plugins: ${plugins[*]}" | fmt

for p in "${plugins[@]}"; do
    [[ $p = httcheck ]] && continue
    version=$(awk -v plugin=$p '$1 == plugin {print $2}' <<<"$plugin_ver")
    mkdir $p
    # linux
    os=linux
    for arch in x86_64 x86; do
        m="plugins_${os}_${arch}"
        if [[ -x $m/bin/$p ]]; then
            mkdir -p $p/$m/$p/{etc,bin}
            # 二进制和脚本
            cp -a $m/bin/$p $p/$m/$p/bin/
            cp -a $m/bin/*.sh $p/$m/$p/bin/
            # get gse_desc_info from project.yaml
            get_single_plugin_desc_info $m/project.yaml $p > $p/$m/$p/project.yaml
            # append launch code
            echo 'launch_node: all' >> $p/$m/$p/project.yaml
            # append control info 
            get_single_plugin_control_info $os $p >> $p/$m/$p/project.yaml
            # 生成配置文件
            for f in support-files/templates/${m}\#etc\#*${p}*; do
                cp -a "$f" $p/$m/$p/etc/${f##*#}
            done 
        fi
    done
    # linux
    os=windows
    for arch in x86_64 x86; do
        m="plugins_${os}_${arch}"
        if [[ -x $m/bin/${p}.exe ]]; then
           mkdir -p $p/$m/$p/{etc,bin}
           # 二进制和脚本
           cp -a $m/bin/${p}.exe $p/$m/$p/bin/
           cp -a $m/bin/*.sh $m/bin/*.bat $p/$m/$p/bin/
           # get gse_desc_info from project.yaml
           get_single_plugin_desc_info $m/project.yaml $p > $p/$m/$p/project.yaml
           # append launch code
           echo 'launch_node: all' >> $p/$m/$p/project.yaml
           # append control info 
           get_single_plugin_control_info $os $p >> $p/$m/$p/project.yaml
           # 生成配置文件
           for f in support-files/templates/${m}\#etc\#*${p}*; do
               cp -a "$f" $p/$m/$p/etc/${f##*#}
           done 
        fi
    done
    output_tgz=$GSE_OUTPUT_DIR/${p}-${version}.tgz
    echo "pack plugin <$p-$version>, output: $output_tgz"
    ( cd $p && tar -czf $output_tgz * )
done
