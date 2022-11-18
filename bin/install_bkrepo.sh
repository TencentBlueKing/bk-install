#!/usr/bin/env bash
# 用途： 安装蓝鲸的bkrepo系统.

# 安全模式
set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")

# 支持的工程名称及处理函数. 默认为 install_repo_microservice_default
declare -A PROJECTS=(
  ["frontend"]=install_module_proj
  # 兼容名称: web
  ["web"]=install_repo_gateway
  # 一些需要特殊处理的模块
  ["gateway"]=install_repo_gateway
)

# 基准内存大小. 单位MB. 建议 256-2048.
BKREPO_MICROSERVICE_RAM_BASELINE_MB=1024
# 不同的微服务会使用不同的倍率. 默认factor为1. 基准及倍率只能为整数.
BKREPO_MICROSERVICE_RAM_FACTOR_DEFAULT=1
declare -A BKREPO_MICROSERVICE_RAM_FACTOR=(
)
declare -A BKREPO_MICROSERVICE_RAMS_MB

# install函数: 复制文件.
# Usage: install_module_proj MODULE PROJ
install_module_proj() {
  local module=$1
  local proj=$2
  [ -z "$module" ] && fail "Usage: $FUNCNAME MODULE PROJ"
  [ -z "$proj" ] && fail "Usage: $FUNCNAME MODULE PROJ"
  # 确保MODULE存在.
  [ -d "$MODULE_SRC_DIR/${module:-xxx}" ] || fail "ERROR: $FUNCNAME: module not exist in dir $MODULE_SRC_DIR: $module"
  [ -d "$MODULE_SRC_DIR/${module:-xxx}/${proj:-xxx}" ] || fail "ERROR: $FUNCNAME: proj not exist in dir: $MODULE_SRC_DIR/$module"
  # 使用rsync增量复制. 不删除目的目录的其他文件.
  rsync -a "$MODULE_SRC_DIR/$module/$proj" "$PREFIX/$module/"
  rsync -a "$MODULE_SRC_DIR/$module/VERSION" "$PREFIX/$module/"
}

install_repo_microservice_default() {
  local module="$1"
  local proj="$2"
  install_module_proj "$module" "backend"
  generate_service_repo_microservice "$proj"
}

consul_kv_put_repo_config (){
  local i k f v
  for i in "$@"; do
    k="bkrepo-config/$i/data"
    f="${PREFIX:-/data/bkce}/etc/bkrepo/$i.yaml"
    echo >&2 "consul kv put $k from file: $f."
    consul kv put "$k" "-" < "$f"
  done
}
# fix link target.
# param 1: linkpath, if not exist, will create, if exist and a link, fix its target, otherwise fail.
# param 2: expected target
fix_link (){
    local target="$1"
    local linkpath="$2"
    [ -z "$linkpath" -o -z "$target" ] && { fail "Usage: $FUNCNAME linkpath target  -- update link to target."; return 3; }
    [ ! -e "$linkpath" -o -L "$linkpath" ] || { fail "$FUNCNAME: linkpath($linkpath) exist and not a link."; return 2; }
    log "$FUNCNAME: link $linkpath point to $target."
    ln -sfT "$target" "$linkpath" || { fail "$FUNCNAME: fail when update link."; return 1; }
}
# 参数为 install_repo_gateway repo gateway, 但是没必要处理.
install_repo_gateway() {
  local module=bkrepo
  local proj=gateway
  local logroot="$PREFIX/logs"
  local logdir="$logroot/$module"
  install_openresty
  install_module_proj "$module" "gateway"
  install_module_proj "$module" "frontend"
  # 链接: openresty nginx的conf(repo/gateway), log(logs/repo/nginx), run(logs/run)目录.
  log "setup openresty config dirs."
  local openresty_nginx_home="/usr/local/openresty/nginx"
  [ -d "$openresty_nginx_home" ] || fail "dir openresty_nginx_home($openresty_nginx_home) is not exist."
  # 如果不是链接, 则备份. 如果备份目录存在, 则会移到备份目录里面...
  [ -L "$openresty_nginx_home/conf" ] || {
    local conf_dir_back_path="$openresty_nginx_home/conf-rpmbak"
    log "backup original openresty conf dir as $conf_dir_back_path"
    mv "$openresty_nginx_home/conf" "$conf_dir_back_path"
  }
  fix_link "$PREFIX/$module/gateway" "$openresty_nginx_home/conf" || fail "Abort"
  mkdir -p "$logdir/nginx" "$logroot/run" || fail "Abort"
  chmod 777 "$logdir/nginx" "$logroot/run" || fail "Abort"
  fix_link "$logroot/run" "$openresty_nginx_home/run" || fail "Abort"
  fix_link "$logdir/nginx" "$openresty_nginx_home/log" || fail "Abort"

  # 修正nginx启动用户.
  local user=blueking
  echo >&2 "  openresty should run as $user"
  local nginx_conf="$openresty_nginx_home/conf/nginx.conf"
  if grep -qE "^[ \t]*user[ \t]" "$nginx_conf"; then
    sed -i "s/^[ \t]*user.*$/  user $user;/" "$nginx_conf"
  else
    sed -i '1 i   user blueking;' "$nginx_conf"
  fi
  grep -E "^[ \t]*user[ \t]" "$nginx_conf"
  #log "register consul service for openresty(repo,codecc,repo-op)"
  #source "$CTRL_DIR/repo/repo.env"
  #for svc in repo codecc repo-op; do
  #    $CTRL_DIR/bin/reg_consul_svc -n $svc -p $BKREPO_HTTP_PORT -a $LAN_IP
  #done
  generate_service_repo_gateway
}
# 依赖的安装, 请使用对应的独立脚本.
install_java() {
  echo "you could install java by using install-java.sh."
}
install_docker() {
  echo "you could install docker by using install-docker.sh."
}
install_openresty() {
  echo "you could install openresty by using install-openresty.sh."
}

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

MODULE=bkrepo

ENV_FILE=

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -m, --module      [可选] "安装的子模块(${!PROJECTS[*]-}), 默认都会安装" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]
            [ -s, --srcdir      [必填] "从该目录拷贝open_paas/module目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ -l, --log-dir     [可选] "日志目录,默认为$PREFIX/logs/open_paas" ]
            [ -v, --version     [可选] 查看脚本版本号 ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

debug() {
  [ -z "$DEBUG" ] || echo >&2 "$@"
}

log () {
    echo >&2 "$@"
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

version () {
    echo "$PROGRAM version $VERSION"
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do
    case "$1" in
        -e | --env-file)
            shift
            ENV_FILE="$1"
            ;;
        -s | --srcdir )
            shift
            MODULE_SRC_DIR=$1
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

[ -z "$MODULE" ] && fail "ERROR: var MODULE is empty or not set."
LOG_DIR=${LOG_DIR:-$PREFIX/logs/$MODULE}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/$MODULE ]]; then
    warning "$MODULE_SRC_DIR/$MODULE 不存在"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

# 探测微服务:
BKREPO_MIRCOSERVICES=( $(test -d "$MODULE_SRC_DIR/bkrepo/backend" && cd "$MODULE_SRC_DIR/bkrepo/backend" &&  ls -1du service-*.jar 2>/dev/null | sed -r -e 's@(service-|[.]jar)@@g' | sort -u) )
[ ${#BKREPO_MIRCOSERVICES[@]-} -eq 0 ] && fail "ERROR: no bkrepo microservice in dir: $MODULE_SRC_DIR/bkrepo/."
BKREPO_PROJECTS="gateway ${BKREPO_MIRCOSERVICES[*]-}"

service_need_agentpackage="dispatch environment dockerhost"
for proj in ${BKREPO_MIRCOSERVICES[@]-}; do
  # 其他微服务使用默认的 install_repo_microservice_default
  if [ -z "${PROJECTS[$proj]-}" ]; then
    PROJECTS[$proj]=install_repo_microservice_default
  fi
  if [ -z "${BKREPO_MICROSERVICE_RAM_FACTOR[$proj]-}" ]; then
    # 使用默认的倍率.
    BKREPO_MICROSERVICE_RAM_FACTOR[$proj]=$BKREPO_MICROSERVICE_RAM_FACTOR_DEFAULT
  fi
  # 同时计算微服务的内容用量
  BKREPO_MICROSERVICE_RAMS_MB[$proj]=$((${BKREPO_MICROSERVICE_RAM_FACTOR[$proj]-}*$BKREPO_MICROSERVICE_RAM_BASELINE_MB))
done

# 安装用户和配置目录
id -u blueking &>/dev/null || \
    useradd -m -d /home/blueking -c "BlueKing EE User" --shell /bin/bash blueking

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env
install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"
install -o blueking -g blueking -m 755 -d /var/run/$MODULE
install -o blueking -g blueking -m 755 -d "$PREFIX/public/$MODULE"  # 上传下载目录

# 仅创建unit文件
systemd_unit_set() {
  local conf="/usr/lib/systemd/system/$1"
  cat > "$conf"
  chown blueking:blueking "$conf"
  systemctl daemon-reload
}
# 创建service unit文件和sysconfig的env文件.
#systemd_service_set() {
#  local service=$1
#  sysconfig_update "$service"
#}

# 这里仅负责更新文件的对应KEY, set请使用 systemd_service_set.
# 那么是原位置更新? 还是追加到结尾?
# environmentfile 等号前后允许空白. https://www.freedesktop.org/software/systemd/man/systemd.exec.html
sysconfig_kv_set() {
  local service=$1
  shift
  if [ -z "$service" ] || [ $# -eq 0 ]; then
     echo >&2 "Usage: $FUNCNAME SERVICE KVs...  -- update sysconfig K-V for SERVICE";
     return 1;
  fi
  local conf="/etc/sysconfig/$service"
  touch "$conf" || { echo >&2 "cant touch file: $conf"; return 3; }
  # 预处理插入语句.
  local patt_kv_define="^[a-zA-Z][a-zA-Z0-9_]*=.*$"
  local delete_line k v
  for kv in "$@"; do
    k=${kv%%=*}
    v=${kv#*=}
    # 检查参数语法.
    # 检查配置文件的配置项
    if [[ "$kv" =~ $patt_kv_define ]]; then
      # 检查kv定义是否存在
      if grep -q "^${k}[ \t]*=[ \t]*.*" "$conf"; then
        : 检查内容是否匹配, 不匹配则刷新.
      else  # 追加更新.
        echo >&2 "  append kv($kv) to conf($conf)."
        # 注意使用转义后的字符串.
        echo "$kv" >> "$conf"
      fi
    else
      echo >&2 "invalid kv item, KV($kv) does not match pattern($patt_kv_define)."
    fi
  done
  # 更新sysconfig文件.
  # 删除旧配置, 追加新配置.
}

# 额外的服务依赖, 空格分隔的systemd service名. 会添加到After=和Requires=属性后面.
# 一些特殊的公共依赖请直接修改模板文件.
declare -A MICROSERVICE_Requires=(
  #[""]=""
  ["image"]="docker.service"
  ["agentless"]="docker.service"
  ["dockerhost"]="docker.service"
  # 使用 assembly 时, 也应该依赖本地的docker.
  ["assembly"]="docker.service"
)
# 一些服务的启动检查:
declare -A MICROSERVICE_ExecStartPre=(
  #[""]=""
  # agentless依赖查询dispatch, 但是未必在同一节点, 所以需要等待dispatch启动.
  ["agentless"]="bash -c 'until host dispatch-devops.service.consul; do s=\$((SECONDS/7+1));echo \"waiting service(repo-dispatch) ready for \${s}s...\"; sleep \"\$s\"; done'"
)
declare -A MICROSERVICE_ExecStartPost=(
)
declare -A MICROSERVICE_ExecStopPost=(
)
# 暂无默认post.

# 生成微服务的service文件.
generate_service_repo_microservice() {
  local module=bkrepo
  local service="$1"
  . "$ENV_FILE"
  local full_service="bk-repo-$service"
  local CERT_PATH="${CERT_PATH:-$PREFIX/cert}"
  local cert_file="$CERT_PATH/bkci_platform.cert"
  local CONF_HOME="$PREFIX/etc/$module/"
  local LOGS_HOME="$PREFIX/logs/$module/$service/"
  local JAR_FILE="$PREFIX/$module/backend/service-$service.jar"
  # 检查JAR_FILE
  if ! [ -f "$JAR_FILE" ]; then
    echo >&2 "ERROR: $FUNCNAME: JAR_FILE($JAR_FILE): no such file."
    return 1
  fi
  # 如果没有配置内存限制, 则指示问题所在.
  local ram_size=${BKREPO_MICROSERVICE_RAMS_MB[$service]-}
  if [ -n "$ram_size" ]; then
    ram_size="${ram_size}M"  # 这里的单位需要大写. 小写的在linux上报错.
  else
    echo >&2 "ERROR: cant determine ram_size for service: $service.";
    exit 42  # 试图直接退出脚本. 提示此重要故障.
  fi
  # 检测 BK_REPO_PRIVATE_URL, 用于集群内部访问网关.
  if [ -z "$BK_REPO_PRIVATE_URL" ]; then
    echo >&2 "ERROR: var BK_REPO_PRIVATE_URL is empty. it should be http://bk-repo.service.\$BK_REPO_CONSUL_DOMAIN"
    echo >&2 "TIPS: you may register it by consul:"
    echo >&2 "pcmd bkrepo_web '/data/install/bin/reg_consul_svc -n bk-repo -p 80 -a \$LAN_IP -D > /etc/consul.d/service/bk-repo.json; consul reload'"
    exit 44
  fi
  # consul ServiceID, 默认取主机名. 需要保证主机名唯一, 否则会被视同为同一实例.
  # 开发已经更新了代码. 去掉 -Dspring.cloud.consul.discovery.instanceId=$service_id
  #local service_id="${service}-devops-${HOSTNAME:-HOSTNAME-is-empty}"
  #sysconfig_update "$full_service" "NAME" "value"  # update env file NAME=value
  # 这里的变量和service文件对应, 需要人工维护.
  #sysconfig_kv_set "$full_service" MEM_OPTS="-Xms2g -Xmx3g" \
  #  GATEWAT_OPTS="-Ddevops_gateway=http://devops.oa.com:80" \
  #  LOG_OPTS="-Dservice.log.dir=${LOGS_HOME}" \
  #  CONFIG_OPTS="-Dspring.config.location=file:${CONF_HOME}/common.yml,file:${CONF_HOME}/application-${service}.yml" \
  #  SECURE_OPTS="-Dcertificate.file=${CERT_PATH}/bkci_platform.cert -Djava.security.egd=file:/dev/./urandom"

  # 尽量使用低权限用户执行.
  local user
  if [ "$service" = "agentless" ] || [ "$service" = "dockerhost" ]; then
    user=root
  else
    user=blueking
  fi
  systemd_unit_set "${full_service}.service" <<EOF
[Unit]
Description=${full_service}.service
After=network-online.target
# consul.service ${MICROSERVICE_Requires[$service]-}
# 强依赖. 如果consul退出, 微服务也应该退出, 毕竟无法进行服务发现了. 那么consul停止并恢复后, 如何自动启动呢?
#Requires=consul.service ${MICROSERVICE_Requires[$service]-}
# 弱依赖.
Wants=
PartOf=bk-repo.target

[Service]
# TODO: 需要考虑dockerhost image agentless等调用docker的问题.
User=$user
# 使用Environment提供默认变量值. 允许EnvironmentFile覆盖.
Environment='MEM_OPTS=-Xms${ram_size} -Xmx${ram_size}'
#Environment='BK_OPTS=-Ddevops_gateway=$BK_REPO_PRIVATE_URL -Dcertificate.file=$cert_file -classpath $PREFIX/$module/plugin/config/'
Environment='CONF_OPTS=-Dspring.profiles.active=dev -Dspring.cloud.consul.port=8500'
Environment='RUNTIME_OPTS=-XX:NewRatio=1 -XX:SurvivorRatio=8 -XX:+UseConcMarkSweepGC -Djava.security.egd=file:/dev/./urandom'
# 默认无JAVA_OPTS, 允许用户自定义.
EnvironmentFile=-/etc/sysconfig/${full_service}
WorkingDirectory=${PREFIX}/bkrepo/backend
ExecStart=/usr/bin/env java -server -Dfile.encoding=UTF-8 \$MEM_OPTS \$CONF_OPTS \$RUNTIME_OPTS \$BK_OPTS \$JAVA_OPTS -jar $JAR_FILE
ExecStartPre=${MICROSERVICE_ExecStartPre[$service]-}
ExecStartPost=${MICROSERVICE_ExecStartPost[$service]-}
ExecStopPost=${MICROSERVICE_ExecStopPost[$service]-}
#ExecStop=/bin/kill \$MAINPID
StandardOutput=journal
StandardError=journal
SuccessExitStatus=143
LimitNOFILE=204800
LimitCORE=infinity
TimeoutStopSec=35
TimeoutStartSec=300
Restart=always
RestartSec=5

[Install]
# 期望在consul启动后自动启动微服务.
WantedBy=bk-repo.target
EOF
}

generate_service_repo_gateway() {
  local nginx_bin_dir=/usr/local/openresty/nginx
  systemd_unit_set bk-repo-gateway.service <<EOF
[Unit]
Description=BK REPO gateway.
After=network-online.target
PartOf=bk-repo.target

[Service]
Type=forking
PIDFile=$nginx_bin_dir/run/nginx.pid
WorkingDirectory=$nginx_bin_dir
ExecStartPre=$nginx_bin_dir/sbin/nginx -t
ExecStart=$nginx_bin_dir/sbin/nginx
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true
TimeoutStopSec=60

[Install]
WantedBy=bk-repo.target
EOF
}

# 生成bk-repo.target
systemd_unit_set bk-repo.target <<EOF
[Unit]
Description=BK REPO target to allow start/stop all bk-repo-*.service at once

[Install]
WantedBy=multi-user.target blueking.target
EOF


# 拷贝模块目录到$PREFIX
#rsync -a --delete "${MODULE_SRC_DIR}"/repo "$PREFIX/"

# 判断本机需要启用的服务:
LAN_IP=$(ip r get 10/8 | awk '/10/{print $NF}')
[ -z "$LAN_IP" ] && fail "cant get LAN_IP."
expected_projects=$(awk -F"[ ,]+" -v ip="$LAN_IP" '$1==ip{
  for(i=2;i<=NF;i++){
    if($i~/^bkrepo\(/){
      gsub(/bkrepo\(|\)/, "", $i);
      sub("^web$", "gateway", $i)
      print $i
    }
  }
}' "/data/install/install.config")

# 基于install.config决定当前节点应该启用/禁用的服务.
for proj in $expected_projects; do
    svc_name="bk-repo-$proj"
    ${PROJECTS[$proj]} "$MODULE" "$proj"
    if systemctl is-enabled "$svc_name" &>/dev/null; then
      echo "service has enabled: $svc_name"
    else
      systemctl enable "$svc_name"
    fi
done
# 渲染配置
"$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
    -e "$ENV_FILE" \
    "$MODULE_SRC_DIR/$MODULE/support-files/templates/"*
# 刷新consul key, 后续应该移入中控机执行.
for proj in application ${BKREPO_MIRCOSERVICES[*]-}; do
  consul_kv_put_repo_config "$proj"
done

chown -R blueking:blueking "$PREFIX/bkrepo" "$LOG_DIR"
