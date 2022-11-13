#!/usr/bin/env bash
# 用途： 安装蓝鲸的CI平台.

# 安全模式
set -euo pipefail

## 安装脚本基础变量
# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
# 模块安装后所在的上一级目录
PREFIX=/data/bkee
# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src
MODULE=ci
ENV_FILE=

usage () {
    cat <<EOF
用法:
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -m, --module      [可选] "安装的子模块(${bkci_proj_all// /,}), 逗号分隔." ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]
            [ -s, --srcdir      [必填] "从该目录拷贝open_paas/module目录到--prefix指定的目录" ]
            [ -r, --ram-mb      [废弃] "微服务内存大小, 单位MB. 已废弃." ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ -v, --version     [可选] "查看脚本版本号" ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

debug() {
  [ -z "${DEBUG:-}" ] || echo >&2 "$@"
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

highlight(){
  echo -e "\033[7m  $*  \033[0m"
}

## CI安装所需的变量
# 不再探测微服务. 这里指明支持的proj正式名称. 记得同步更新 bkci_service_heap_size_mb.
bkci_proj_backends=(dockerhost agentless artifactory auth dispatch environment image log misc notify openapi plugin process project quality repository store ticket websocket )
# 全部可用的proj名称.
bkci_proj_all="gateway ${bkci_proj_backends[*]-}"

# 支持的工程名称及处理函数. 默认为 install_ci_microservice_default
declare -A PROJECTS=(
  # agent-package, docs, frontend等作为依赖存在, 考虑允许单独更新. 暂未实现.
  ["agent-package"]=install_ci_agentpackage
  ["docs"]=install_module_proj
  ["frontend"]=install_module_proj
  # 一些需要特殊处理的模块
  ["gateway"]=install_ci_gateway
  ["dockerhost"]=install_ci_dockerhost
  ["agentless"]=install_ci_agentless
  ["artifactory"]=install_ci_artifactory
  ["dispatch"]=install_ci_dispatch
  ["environment"]=install_ci_environment
  ["image"]=install_ci_image
  ["project"]=install_ci_project
  # TODO assembly的逻辑会比较复杂. 暂时不做.
  #["assembly"]=install_ci_assembly
)

# 这里必须列出全部的服务名.
# 这是微服务的最低内存需求，可以自动判断成倍增长。
declare -A bkci_service_heap_size_mb=(
  ["gateway"]=1  # 为了简化检查逻辑，这里也需要写非java微服务的。取值非空即可。
  ["agentless"]=512
  ["artifactory"]=512
  ["auth"]=512
  ["dispatch"]=512
  ["dockerhost"]=512
  ["environment"]=512
  ["image"]=512
  ["log"]=768
  ["measure"]=384
  ["misc"]=384
  ["monitoring"]=384
  ["notify"]=384
  ["openapi"]=512
  ["plugin"]=384
  ["process"]=768
  ["project"]=512
  ["quality"]=512
  ["repository"]=384
  ["store"]=512
  ["ticket"]=384
  ["websocket"]=512
)

# 额外的服务依赖, 空格分隔的systemd service名. 会添加到After=和Requires=属性后面.
# 一些特殊的公共依赖请直接修改模板文件.
# 强依赖.
declare -A systemd_service_requires=(
  #[""]=""
  ["image"]="docker.service"
  ["agentless"]="docker.service"
  ["dockerhost"]="docker.service"
  # 使用 assembly 时, 也应该依赖本地的docker.
  ["assembly"]="docker.service"
)
# 弱依赖.
declare -A systemd_service_wants=(
)
# 一些服务的启动检查:
container_iface=docker0
container_dns_hijack_mark="bk-ci-docker-dns-hijack"  # 用于iptables规则描述及匹配. 无空格.
container_dns_hijack_rule="-i ${container_iface:-container_iface} -p udp -m udp --dport 53 -j DNAT --to-destination 127.0.0.1 -m comment --comment $container_dns_hijack_mark"
container_dns_hijack_script="iptables -t nat -S PREROUTING | grep -- \"$container_dns_hijack_mark\" || { echo \"set dns hijack rule: $container_dns_hijack_rule\"; iptables -t nat -I PREROUTING 1 $container_dns_hijack_rule || exit 41; }; sysctl net.ipv4.conf.${container_iface}.route_localnet=1 || exit 40"
declare -A systemd_service_execstartpre=(
  #[""]=""   # 模板. 如需shell脚本, 可以使用/bin/bash -c '脚本内容'
  # agentless依赖查询dispatch, 但是未必在同一节点, 所以需要等待dispatch启动.
  ["agentless"]="/bin/bash -c 'until getent hosts dispatch-devops.service.consul && getent hosts bk-ci.service.consul; do s=\$((SECONDS/7+1));echo \"waiting service ready for \$\${s}s...\"; sleep \"\$s\"; done; $container_dns_hijack_script'"
  ["dockerhost"]="/bin/bash -c 'until getent hosts bk-ci.service.consul; do s=\$((SECONDS/7+1));echo \"waiting service ready fors \$\${s}s...\"; sleep \"\$s\"; done; $container_dns_hijack_script'"
)
declare -A systemd_service_execstartpost=(
)
declare -A systemd_service_execstoppost=(
)


## 函数
### 基础功能
#### 检查环境变量
# 检查提示一批环境变量是否为空.
# param name...: 变量名
# return empty_count: 不存在的变量数量.
var_check() {
  local empty_count=0 name
  for name in $@; do
    if [ -z "${!name:-}" ]; then
      log "WARNING: var $name is empty or not set."
      let ++empty_count  # 提前++, 避免let求值结果为0返回1.
    fi
  done
  return $empty_count
}
# 目前仅yum安装.
os_pkg_install() {
  local pkg
  debug "os_pkg_install: $*"
  for pkg in "$@"; do
    if ! rpm -q "$pkg" >/dev/null; then
      yum -y install "$pkg"
    fi
  done
}
# 依赖的安装
install_java() {
  echo "check java"
  # 建议考虑直接使用蓝鲸的 bin/install_java.sh脚本安装. 具体参考蓝鲸文档.
  local java_exe="/usr/bin/java"
  if ! [ -x "$java_exe" ]; then
    os_pkg_install java-1.8.0-openjdk   # 如无则默认使用openjdk.
  fi
}
install_docker() {
  echo "install docker"
  os_pkg_install docker-ce
  # 允许控制docker, image需要和docker通信.
  usermod -aG docker blueking
}
install_openresty() {
  echo "install openresty"
  os_pkg_install openresty
}

# 仅创建unit文件
systemd_unit_set() {
  local conf="/usr/lib/systemd/system/$1"
  cat > "$conf"
  chown root:root "$conf"
  systemctl daemon-reload
}

# install函数: 复制文件.
# Usage: install_module_proj MODULE PROJ
install_module_proj() {
  local module=$1
  local proj=$2
  [ -z "$module" ] && fail "Usage: $FUNCNAME MODULE PROJ"
  [ -z "$proj" ] && fail "Usage: $FUNCNAME MODULE PROJ"
  # 确保MODULE存在.
  [ -d "$MODULE_SRC_DIR/${module:-xxx}" ] || fail "ERROR: $FUNCNAME: module not exist in dir: $MODULE_SRC_DIR"
  [ -d "$MODULE_SRC_DIR/${module:-xxx}/${proj:-xxx}" ] || fail "ERROR: $FUNCNAME: proj not exist in dir: $MODULE_SRC_DIR/$module"
  # 使用rsync增量复制. 不删除目的目录的其他文件.
  rsync -a "$MODULE_SRC_DIR/$module/$proj" "$PREFIX/$module/"
  rsync -a "$MODULE_SRC_DIR/$module/VERSION" "$PREFIX/$module/"
}

#### 修正链接
# 用于确保给定的链接符合预期.
# param : linkpath, if not exist, will create, if exist and a link, fix its target, otherwise fail.
# param 2: expected target
fix_link (){
    local target="$1"
    local linkpath="$2"
    [ -z "$linkpath" -o -z "$target" ] && { fail "Usage: $FUNCNAME linkpath target  -- update link to target."; return 3; }
    [ ! -e "$linkpath" -o -L "$linkpath" ] || { fail "$FUNCNAME: linkpath($linkpath) exist and not a link."; return 2; }
    log "$FUNCNAME: link $linkpath point to $target."
    ln -sfT "$target" "$linkpath" || { fail "$FUNCNAME: fail when update link."; return 1; }
}

### 安装信息收集
#### 根据变量判断本机应该安装的微服务
# var LAN_IP: 本机IP
# var BK_CI_PROJ_IP_COMMA: PROJ对应的IP清单. bk环境下source load_env.sh时设置.
# var bkci_proj_all: 本脚本维护的全部proj清单, 空格分隔.
# var-set expected_proj_all: 输出proj清单, 空格分隔.
detect_ci_proj_by_env() {
  # 提供兼容变量, 处理历史名称.
  : ${BK_CI_GATEWAY_IP_COMMA:=${BK_CI_WEB_IP_COMMA-}}
  : ${BK_CI_DOCKERHOST_IP_COMMA:=${BK_CI_BUILD_IP_COMMA-}}
  local k v
  declare -g expected_proj_all=""  # 清空此变量.
  for proj in $(echo "${bkci_proj_all// /$'\n'}" | sort -u); do
    k=BK_CI_${proj^^}_IP_COMMA
    v=",${!k-},"
    debug "detect_ci_proj_by_env: LAN_IP: $LAN_IP, k: $k, v: $v."
    if [[ "$v" == *,$LAN_IP,* ]]; then
      expected_proj_all="$expected_proj_all $proj"
    fi
  done
  return 0
}
# 计算CI微服务的内存倍率
# usage: calc_bkci_heap_size_ratio ms...
# var BKCI_AVAIL_RAM_MB: 整数, CI微服务可用的内存数量.
# params ms: 服务名
# return heap_size_ratio: 内存倍率. 0-6, 为0则失败. 2为默认(无法获取系统内存时).
# 0失败时, 可能因为总内存不满足, 或存在异常的服务名.
# 低于2则提示. 建议重新分配节点数量.
# 止步6, 如依旧不能满足需求, 建议增加节点数量.
calc_bkci_heap_size_ratio (){
  local heap_size_ratio_default=2
  local heap_size_ratio_max=6
  local heap_size_ratio=0
  local dockerhost_node=0 heap_size_ratio_dockerhost=0
  local ms heap_size_sum ms_ram_sum heap_size_ratio ms_count estimated_ram_sum_mb
  for ms in "$@"; do
    if [ "$ms" = "agentless" -o "$ms" = "dockerhost" ]; then
      dockerhost_node=1
    fi
    if [ -z "${bkci_service_heap_size_mb[$ms]:-}" ]; then
      echo "ERROR: invalid service: bkci_service_heap_size_mb[$ms] is empty."
      return 0
    fi
    let heap_size_sum+=${bkci_service_heap_size_mb[$ms]}
    let ++ms_count
  done
  # java总内存开销约为堆内存的1.2倍. 实际上不同的微服务逻辑不同, 此值会有差异.
  ms_ram_sum=$(( heap_size_sum + heap_size_sum / 5 ))
  if [ ${BKCI_AVAIL_RAM_MB:-0} -eq 0 ]; then
    echo "WARNING: BKCI_AVAIL_RAM_MB 无效, 无法判断系统内存，使用默认的 heap_size_ratio: $heap_size_ratio_default";
    heap_size_ratio=$heap_size_ratio_default;
    heap_size_ratio_dockerhost=$heap_size_ratio_default;
  else
    # 倍率计算.
    heap_size_ratio=$(( BKCI_AVAIL_RAM_MB / ms_ram_sum ))
    # dockerhost只负责管理本机容器，内存没必要太高，应为系统的1/32。但倍率应至少为1。
    heap_size_ratio_dockerhost=$(( BKCI_AVAIL_RAM_MB / 32 / ${bkci_service_heap_size_mb["dockerhost"]} + 1 ))
  fi
  if [ $heap_size_ratio -eq 0 ]; then
    echo "ERROR: 内存不足。可用: $BKCI_AVAIL_RAM_MB, 至少需要: $ms_ram_sum."
    return 0
  elif [ $heap_size_ratio -lt $heap_size_ratio_default ]; then
    echo "WARNING: 当前内存略低。已自动降低内存用量，请在必要时扩容内存或增加部署节点以降低负载。"
  elif [ $heap_size_ratio -gt $heap_size_ratio_max ]; then
    # echo "TIP: heap_size_ratio($heap_size_ratio) is greater than max($heap_size_ratio_max)."
    heap_size_ratio=$heap_size_ratio_max
  fi
  if [ $dockerhost_node -gt 0 ] && [ $heap_size_ratio_dockerhost -lt $heap_size_ratio ]; then
    echo "INFO: dockerhost 服务的内存过高，heap_size_ratio 从 $heap_size_ratio 降为 $heap_size_ratio_dockerhost。"
    [ $ms_count -gt 1 ] && echo "TIPS: 尽量不要将 dockerhost 和其他微服务部署到同一节点。"
    heap_size_ratio=$heap_size_ratio_dockerhost
  fi
  # 计算出最终的内存消耗预估值。
  estimated_ram_sum_mb=$((ms_ram_sum * heap_size_ratio))
  echo "RAM_RATIO_RESULT ms_count=$ms_count; heap_size_ratio=$heap_size_ratio; estimated_ram_sum_mb=$estimated_ram_sum_mb"
  return $heap_size_ratio
}

# CI总内存应小于系统内存的85%。
get_bkci_avail_ram_mb (){
  BKCI_AVAIL_RAM_MB=$( awk '/ cgroup .*\<memory\>/{
  getline < sprintf($2"/memory.limit_in_bytes"); limit_mb=$1/1024/1024; }
  END{ getline < "/proc/meminfo"; meminfo_mb=$2/1024;
  if(limit_mb && meminfo_mb > limit_mb){ meminfo_mb=limit_mb; }
  printf "%.0f", meminfo_mb * 0.85; }' /proc/mounts 2>/dev/null )
  return 0
}

## 执行安装
# 安装ci基础.
install_ci_common() {
  # 安装用户和配置目录
  id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; }

  install -o blueking -g blueking -d "${BK_CI_LOGS_DIR}"
  install -o blueking -g blueking -d "${BK_CI_DATA_DIR}"
  install -o blueking -g blueking -m 755 -d /etc/blueking/env
  install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"
  install -o blueking -g blueking -m 755 -d /var/run/$MODULE
  install -o blueking -g blueking -m 755 -d "$PREFIX/public/$MODULE"  # 上传下载目录

  # 生成bk-ci.target
  systemd_unit_set bk-ci.target <<EOF
[Unit]
Description=BK CI target to allow start/stop all bk-ci-*.service at once

[Install]
WantedBy=blueking.target multi-user.target
EOF
  # 启用target.
  systemctl reenable bk-ci.target
}
# 生成docker配置
gen_docker_config() {
  [ -z "$1" ] && fail "Usage: $FUNCNAME /path/to/daemon.json"
  cat > "$1" <<EOF
{
    "data-root": "$docker_root",
    "iptables": true,
    "live-restore": true,
    "ip-forward": true,
    "insecure-registries": [
    ]
}
EOF
}
# 安装ci docker, 主要是配置文件修改
install_ci_docker() {
  install_docker
  local docker_root=$BK_HOME/public/docker-bkci  # 这里不选择放入ci目录下, 避免后续误chown.
  local daemon_json="/etc/docker/daemon.json"
  local daemon_json_temp=$(mktemp -t bkci-docker-daemon-json-XXXXXX )
  mkdir -p /etc/docker/ $docker_root
  gen_docker_config "$daemon_json_temp"
  debug "generate temp docker config: $daemon_json_temp"
  if diff "$daemon_json" "$daemon_json_temp" &>/dev/null; then
    echo "$daemon_json is same as $daemon_json_temp, do nothing."
  else
    if [ -f "$daemon_json" ]; then
      echo "$daemon_json is diff with $daemon_json_temp, do backup."
      cp -v "$daemon_json" "$daemon_json.$(date +%Y%m%d-%H%M%S).bak"
    fi
    echo "overwrite $daemon_json:"
    cp -v "$daemon_json_temp" "$daemon_json" || fail "failed to overwrite $daemon_json."
  fi
  debug "clean temp docker config: $daemon_json_temp"
  rm "$daemon_json_temp"
  return 0
}

# 仅安装当前节点的.
install_ci_agentpackage() {
  local wrong_dir="$PREFIX/$MODULE/agent-package/script/init.sh/"
  if [ -d "$wrong_dir" ]; then rmdir "$wrong_dir"; fi
  install_module_proj "ci" "agent-package"
}
# 默认的CI微服务安装脚本.
install_ci_microservice_default() {
  local module="$1"
  local proj="$2"
  install_java
  install_module_proj "$module" "$proj"
  generate_service_ci_microservice "$proj"
  render_ci_microservice "$proj"
}

# 参数为 install_ci_gateway ci gateway, 但是没必要处理.
install_ci_gateway() {
  local module=ci
  local proj=gateway
  local logroot="$PREFIX/logs"
  local logdir="$logroot/$module"
  install_openresty
  install_module_proj "ci" "gateway"
  install_module_proj "ci" "frontend"
  [ -d "$MODULE_SRC_DIR/ci/docs" ] && install_module_proj "ci" "docs"
  # 链接: openresty nginx的conf(ci/gateway), log(logs/ci/nginx), run(logs/run)目录.
  log "setup openresty config dirs."
  local openresty_nginx_home="/usr/local/openresty/nginx"
  [ -d "$openresty_nginx_home" ] || fail "dir openresty_nginx_home($openresty_nginx_home) is not exist."
  # 如果不是链接, 则备份. 如果备份目录存在, 则会移到备份目录里面...
  [ -L "$openresty_nginx_home/conf" ] || {
      local conf_dir_back_path="$openresty_nginx_home/conf-rpmbak"
      log "backup original openresty conf dir as $conf_dir_back_path"
      mv "$openresty_nginx_home/conf" "$conf_dir_back_path"
  }
  fix_link "$PREFIX/$module/gateway/core" "$openresty_nginx_home/conf" || fail "Abort"
  mkdir -p "$logdir/nginx" "$logroot/run" || fail "Abort"
  chmod 777 "$logdir/nginx" "$logroot/run" || fail "Abort"
  fix_link "$logroot/run" "$openresty_nginx_home/run" || fail "Abort"
  fix_link "$logdir/nginx" "$openresty_nginx_home/log" || fail "Abort"

  # 检查补齐 bk_login_v3 的lua文件.
  local auth_user_v3="conf/lua/auth/auth_user-bk_login_v3.lua"
  local auth_user_v3_src="conf/lua/auth/auth_user-bk_login.lua"  # 直接复用v2的.
  if [ "${BK_CI_AUTH_PROVIDER:-sample}" = "bk_login_v3" ]; then
    cp -nv "$openresty_nginx_home/$auth_user_v3_src" "$openresty_nginx_home/$auth_user_v3" || \
      fail "failed prepare $openresty_nginx_home/$auth_user_v3"
  fi
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

  # TODO 检测ssl并修改配置文件.

  # 注册网关, 改到文档中手动执行.
  #log "register consul service for openresty(ci,codecc,ci-op)"
  #source "$CTRL_DIR/ci/ci.env"
  #for svc in ci codecc ci-op; do
  #    $CTRL_DIR/bin/reg_consul_svc -n $svc -p $BKCI_HTTP_PORT -a $LAN_IP
  #done
  generate_service_ci_gateway
  render_ci_gateway
}
#
install_ci_dockerhost() {
  local module="$1"
  local proj="$2"
  os_pkg_install iptables   # 需要使用iptables操作dns nat.
  install_ci_docker
  os_pkg_install sysstat
  install_ci_agentpackage
  install_ci_microservice_default "$module" "$proj"
}
install_ci_agentless() {
  local module="$1"
  local proj="$2"
  os_pkg_install iptables   # 需要使用iptables操作dns nat.
  install_ci_docker
  os_pkg_install sysstat
  install_ci_agentpackage
  install_ci_microservice_default "$module" "$proj"
}
install_ci_image() {
  local module="$1"
  local proj="$2"
  install_ci_docker
  install_ci_microservice_default "$module" "$proj"
}
# artifactory 需要在多个节点时判断是否使用共享存储.
install_ci_artifactory() {
  local module="$1"
  local proj="artifactory"
  install_ci_microservice_default "$module" "$proj"
  # TODO 检查数据目录是否挂载
  # 判断并复制初始数据.
  local data_dir="$BK_CI_DATA_DIR/$proj/"
  local data_dir_src="$MODULE_SRC_DIR/$module/support-files/file"
  mkdir -p "$data_dir" || fail "failed create artifactory data data_dir."
  chown blueking:blueking "$data_dir"
  echo "sync default artifactory data: $data_dir_src -> $data_dir"
  # rsync时尝试去掉结尾的/.
  rsync -rlvc "${data_dir_src%/}" "$data_dir/"
  echo "fix artifactory file owner."
  find "$data_dir" ! -user blueking -print -exec chown blueking:blueking {} \;
}
# dispatch environment 也依赖agent-package.
install_ci_dispatch() {
  local module="$1"
  local proj="$2"
  install_ci_agentpackage
  install_ci_microservice_default "$module" "$proj"
}
install_ci_environment() {
  local module="$1"
  local proj="$2"
  install_ci_agentpackage
  install_ci_microservice_default "$module" "$proj"
}
install_ci_project() {
  local module="$1"
  local proj="$2"
  os_pkg_install fontconfig
  install_ci_microservice_default "$module" "$proj"
}
## render
# 实现精确render.
do_render_ci() {
  debug "do_render_ci: ${@/#/$MODULE_SRC_DIR/$MODULE/support-files/templates/}"
  # 结尾的$@不加引号, 以便通配到文件.
  "$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
    -e "$ENV_FILE" ${@/#/$MODULE_SRC_DIR/$MODULE/support-files/templates/}
}

render_ci_microservice() {
  local proj=$1
  do_render_ci "#etc#ci#common.yml" "#etc#ci#application-$proj.yml"
}

render_ci_gateway() {
  local proj=gateway
  do_render_ci "gateway#*" "frontend#*"
}

## 启动管理
# 生成微服务的service文件.
generate_service_ci_microservice() {
  local module=ci
  local service="$1"
  local full_service="bk-$module-$service"
  local CERT_PATH="${CERT_PATH:-$PREFIX/cert}"
  local cert_file="$CERT_PATH/bkci_platform.cert"
  local CONF_HOME="$PREFIX/etc/$module/"
  local service_log_dir="$BK_CI_LOGS_DIR/$service/"
  local JAR_FILE="$PREFIX/$module/$service/boot-$service.jar"
  # 检查JAR_FILE
  if ! [ -f "$JAR_FILE" ]; then
    echo >&2 "ERROR: $FUNCNAME: JAR_FILE($JAR_FILE): no such file."
    return 1
  fi
  if [ -z "${bkci_service_heap_size_mb[$service]:-}" ]; then
    echo >&2 "ERROR: bkci_service_heap_size_mb[$service] is empty."
    return 1
  fi
  if [ -z "$BKCI_HEAP_SIZE_RATIO" ]; then
    echo >&2 "ERROR: BKCI_HEAP_SIZE_RATIO is empty."
    return 1
  fi
  # 需要加上单位.
  local ram_size=$(( bkci_service_heap_size_mb[$service] * BKCI_HEAP_SIZE_RATIO ))m
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
After=network-online.target consul.service ${systemd_service_requires[$service]-}
Requires=${systemd_service_requires[$service]-}
# 弱依赖: consul.
Wants=consul.service ${systemd_service_wants[$service]-}
PartOf=bk-ci.target

[Service]
User=$user
# 使用Environment提供默认变量值. 允许EnvironmentFile覆盖.
Environment='MEM_OPTS=-Xms${ram_size} -Xmx${ram_size}'
Environment='BK_OPTS=-Ddevops_gateway=$BK_CI_PRIVATE_URL -Dcertificate.file=$cert_file -classpath $PREFIX/$module/plugin/config/'
Environment='CONF_OPTS=-Dservice.log.dir=${service_log_dir} -Dspring.config.location=file:${CONF_HOME}/common.yml,file:${CONF_HOME}/application-${service}.yml -Dspring.cloud.config.enabled=false'
Environment='RUNTIME_OPTS=-XX:NewRatio=1 -XX:SurvivorRatio=8 -XX:+UseConcMarkSweepGC -Djava.security.egd=file:/dev/./urandom'
# 默认无JAVA_OPTS, 允许用户自定义.
EnvironmentFile=-/etc/sysconfig/${full_service}
WorkingDirectory=${PREFIX}/ci/${service}
ExecStart=/usr/bin/java -server -Dfile.encoding=UTF-8 \$MEM_OPTS \$CONF_OPTS \$RUNTIME_OPTS \$BK_OPTS \$JAVA_OPTS -jar $JAR_FILE
ExecStartPre=${systemd_service_execstartpre[$service]-}
ExecStartPost=${systemd_service_execstartpost[$service]-}
ExecStopPost=${systemd_service_execstoppost[$service]-}
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
WantedBy=bk-ci.target
EOF
}

generate_service_ci_gateway() {
  local nginx_bin_dir=/usr/local/openresty/nginx
  systemd_unit_set bk-ci-gateway.service <<EOF
[Unit]
Description=BK CI gateway.
After=network-online.target
Wants=consul.service
PartOf=bk-ci.target

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
WantedBy=bk-ci.target
EOF
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
        -m | --module )
            shift
            CI_MODULE=$1
            ;;
        -r | --ram-mb )
            shift
            _=$1
            echo >&2 "本脚本已经实现了自动判断内存大小，无需此参数了。"
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

highlight "PRECHECK"
[ -z "$MODULE" ] && fail "ERROR: var MODULE is empty or not set."

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/$MODULE ]]; then
    warning "$MODULE_SRC_DIR/$MODULE 不存在"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) is not readable."
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi

var_check LAN_IP 2>/dev/null || LAN_IP=$(ip r get 10/8 | awk '/10/{print $NF}')
if [ -z "$LAN_IP" ]; then
  fail "Abort. env LAN_IP is not set, and we are failed get LAN_IP, too."
else
  echo "we find an IP as LAN_IP: $LAN_IP"
fi

# 加载ENV文件
source "$ENV_FILE" || fail "failed when source env: $ENV_FILE."
echo "checking ENV in ENV_FILE: $ENV_FILE..."
# 检查一些关键变量
var_check BK_HOME BK_CI_LOGS_DIR BK_CI_DATA_DIR || fail "ERROR: please set ENV first."
# 检测 BK_CI_PRIVATE_URL, 用于集群内部访问网关.
if [ -z "${BK_CI_PRIVATE_URL:-}" ]; then
  echo >&2 "ERROR: var BK_CI_PRIVATE_URL is empty. its value could be http://bk-ci.service.\$BK_CI_CONSUL_DOMAIN"
  echo >&2 "TIPS: you should register the domain in consul:"
  echo >&2 "pcmd.sh -m ci_gateway '/data/install/bin/reg_consul_svc -n bk-ci -p 80 -a \$LAN_IP -D > /etc/consul.d/service/bk-ci.json; consul reload;'"
  exit 44
fi
# 预期LOGS_DIR和DATA_DIR位于BK_HOME下.
if [ "${BK_CI_LOGS_DIR#$BK_HOME}" = "${BK_CI_LOGS_DIR}" ]; then
  fail "ERROR: BK_CI_LOGS_DIR($BK_CI_LOGS_DIR) should begin with BK_HOME($BK_HOME)."
fi
if [ "${BK_CI_DATA_DIR#$BK_HOME}" = "${BK_CI_DATA_DIR}" ]; then
  fail "ERROR: BK_CI_DATA_DIR($BK_CI_DATA_DIR) should begin with BK_HOME($BK_HOME)."
fi
# 预期 BK_HOME 和 PREFIX 相同.
if [ "${BK_HOME%/}" != "${PREFIX%/}" ]; then
  fail "ERROR: BK_HOME($BK_HOME) is not same as -p option: ${PREFIX}."
fi

# 补齐微服务的默认配置.
for proj in ${bkci_proj_backends[@]-}; do
  # 其他微服务使用默认的 install_ci_microservice_default
  if [ -z "${PROJECTS[$proj]-}" ]; then
    PROJECTS[$proj]=install_ci_microservice_default
  fi
done

# 判断本机需要启用的服务:
if [ -z "${CI_MODULE:-}" ]; then
  echo "try detect_ci_proj_by_env..."
  detect_ci_proj_by_env
  if [ -z "$expected_proj_all" ]; then
    error "BlueKing environment variables not found. you should using '-m proj1,proj2' to specify projects to install."
  fi
else
  echo "expected_proj_all is set by -m option."
  expected_proj_all="$(echo "${CI_MODULE//,/$'\n'}" | sed -e 's/^web$/gateway/g' -e 's/^build$/dockerhost/g' | sort -u )"
fi
# 目前agentless和dockerhost不能在同一节点. 因为已排序, 所以这里可以直接按字母次序写patt.
if [[ "$expected_proj_all" == *agentless*dockerhost* ]]; then
  echo "Conflict detect: agentless and dockerhost are both in the same host."
  echo " Tips: try to move dockerhost to another machine, in standalone."
  exit 40
fi

echo "expected_proj_all:" $expected_proj_all
# 安装前的检查.
for proj in $expected_proj_all; do
  if [ -z "${PROJECTS[$proj]-}" ]; then
    #echo >&2 "WARNING: ignore unsupported proj: $proj."
    #continue
    echo >&2 "ERROR: unsupported proj: no installer: $proj."
    exit 4
  fi
  if [ -z "${bkci_service_heap_size_mb[$proj]-}" ]; then
    echo >&2 "ERROR: unsupported proj: bkci_service_heap_size_mb[$proj] is empty."
    exit 4
  fi
done
[ -z "${BKCI_AVAIL_RAM_MB:-}" ] && get_bkci_avail_ram_mb
if calc_bkci_heap_size_ratio $expected_proj_all ; then
  echo "ERROR: insufficient system memory, Abort. 内存不足，停止安装。"
  exit 4
else
  BKCI_HEAP_SIZE_RATIO=$?
  #echo "func calc_bkci_heap_size_ratio returns $heap_size_ratio"
fi

# 正式安装
highlight "INSTALL ci common"
install_ci_common
for proj in $expected_proj_all; do
  svc_name="bk-ci-$proj"
  highlight "INSTALL $svc_name..."
  ${PROJECTS[$proj]-} ci "$proj"
  systemctl reenable "$svc_name"
done

# 渲染全部配置
#echo "render ALL."
#"$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
#  -e "$ENV_FILE" \
#  "$MODULE_SRC_DIR/$MODULE/support-files/templates/"*

highlight "FINISH"
# 修改这些目录的属主
chmod o+rx "$PREFIX"  # 确保prefix有o+rx权限.
for d in "$PREFIX/ci" "$BK_CI_LOGS_DIR"; do
  echo "chown $d to blueking."
  chown -R blueking:blueking "$d"
  # 或许应该确保这些目录的父目录具备o+rw权限?
  # 子目录有属主就够了, 需要修正ug+rx吗?
  #find "$d" -type d -exec chmod o+rx {} \;
done
# 不能chown整个BK_CI_DATA_DIR目录.
# agentless和dockerhost会映射docker, 故docker目录需要保持为root用户, 以便映射到镜像里是root用户.
chown blueking:blueking "$BK_CI_DATA_DIR"
