#!/usr/bin/env bash
# 用途：安装蓝鲸的自监控方案（grafana + promethues）+ 自定义的配置
# 安装概述：
#   1. 安装依赖
#   2. 安装grafana和promethues开源包（rpm/tgz）
#       2.1 wget https://packagecloud.io/prometheus-rpm/release/packages/el/7/prometheus2-2.14.0-2.el7.centos.x86_64.rpm
#       2.2 wget https://dl.grafana.com/oss/release/grafana-6.4.4-1.x86_64.rpm 
#   3. 渲染生成配置
# 参考：
#   1. grafana的配置文件文档：https://grafana.com/docs/installation/configuration/
#   2. prometheus的配置文件文档：https://prometheus.io/docs/prometheus/latest/configuration/configuration/

set -euo pipefail

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
OFFLINE_RPM_DIR=
GRAFANA_VERSION="6.4.4"
PROMETHEUS_VERSION="2.14.0"
BIND_ADDR=

# 浏览器访问grafana时grafana需要用下面的地址告诉浏览器如何查询Prometheus的数据
PROMETHEUS_FQDN=$BIND_ADDR
PROMETHEUS_FQDN_PORT=9090

PROMETHEUS_PORT=9090

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -d, --rpm-dir         [必选] "指定rpm包存放的目录" ]
            [ -n, --domain          [可选] "指定Prometheus的访问域名，默认为bind ip" ]
            [ -b, --bind            [必选] "指定监听的ip" ]
            [ -c, --config-pkg      [必选] "指定selfmonitor的配置包路径" ]
            [ -v, --version         [可选] 查看脚本版本号 ]
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

print_err () {
    read line file <<<$(caller)
    echo "An error occurred in line $line of file $file:" >&2
    sed "${line}q;d" "$file" >&2
}

trap print_error ERR

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -d | --rpm-dir )
            shift
            OFFLINE_RPM_DIR=$1
            ;;
        -b | --bind )
            shift
            BIND_ADDR=$1
            ;;
        -n | --domain )
            shift
            PROMETHEUS_FQDN=$1
            ;;
        -c | --config-pkg )
            shift
            CONFIG_PKG=$1
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
if [[ ! -d "$OFFLINE_RPM_DIR" ]]; then
    warning "不存在 $OFFLINE_RPM_DIR 目录"
fi

if [[ ! -r "$CONFIG_PKG" ]]; then
    warning "不存在 $CONFIG_PKG 文件"
fi

if [[ -z "$BIND_ADDR" ]]; then
    error "-b 参数不能为空，且必须为本机ip地址"
fi

if [[ -z "$(ip addr show to "$BIND_ADDR")" ]]; then
    warning "-b 指定的$BIND_ADDR在本机不存在"
fi

IFS=" " read -r -a pkgs <<< "$(cd "$OFFLINE_RPM_DIR" && echo grafana-${GRAFANA_VERSION}-*.x86_64.rpm promethues2-${PROMETHEUS_VERSION}-*.rpm)"
if (( ${#pkgs[@]} != 2 )); then
    warning "$OFFLINE_RPM_DIR 中不存在 grafana-${GRAFANA_VERSION}-*.x86_64.rpm promethues2-${PROMETHEUS_VERSION}-*.rpm"
fi
if [[ $EXITCODE -ne 0 ]]; then
    exit "$EXITCODE"
fi

# 安装依赖
yum -y install initscripts urw-fonts

# 安装或者升级grafana
if ! rpm -q grafana-${GRAFANA_VERSION} > /dev/null; then
    rpm -Uvh "$OFFLINE_RPM_DIR/grafana-${GRAFANA_VERSION}-*.rpm"
fi

# 安装或者升级prometheus
if ! rpm -q prometheus2-${PROMETHEUS_VERSION} > /dev/null; then
    rpm -Uvh "$OFFLINE_RPM_DIR/prometheus2-${PROMETHEUS_VERSION}-*.rpm"
fi

# 生成配置
# prometheus:
cat > /etc/prometheus/prometheus.yml <<'EOF'
# my global config
global:
  scrape_interval:     15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Alertmanager configuration
alerting:
  alertmanagers:
  - static_configs:
    - targets:
      # - alertmanager:9093

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
  - job_name: 'data_source_sd'
    consul_sd_configs: 
      - server: 'localhost:8500'
      - scheme: 'http'
      - services: 
        - 'bkmonitorv3'
EOF

# 替换prometheus 启动参数
[[ -f /etc/default/prometheus ]] || cp -a /etc/default/prometheus /etc/default/prometheus.orig
if grep -q web.listen-address /etc/default/prometheus 2>/dev/null; then
    sed -i -r "s/--web.listen-address=.*[0-9]+/--web.listen-address=$BIND_ADDR:$PROMETHEUS_PORT/" /etc/default/prometheus
else
    sed -i "s/'$/ --web.listen-address=$BIND_ADDR:$PROMETHEUS_PORT'/" /etc/default/prometheus
fi

# grafana:
# 调整grafana.ini
[[ -f /etc/grafana/grafana.ini.orig ]] || cp -a /etc/grafana/grafana.ini /etc/grafana/grafana.ini.orig
sed -i '/app_mode/s/^;//' /etc/grafana/grafana.ini
sed -i "/http_addr/s/^;//; /http_addr/s/=.*$/= $BIND_ADDR/" /etc/grafana/grafana.ini

# 生成datasources
cat > /etc/grafana/provisioning/datasources/bk_prometheus.yaml <<EOF
# # config file version
apiVersion: 2

datasources:
    - name: bk_prometheus
      type: prometheus
      orgId: 1
      version: 0
      url: http://$PROMETHEUS_FQDN:$PROMETHEUS_FQDN_PORT
      jsonData:
          graphiteVersion: "1.1"
          tlsSkipVerify: true
      editable: true
EOF

log "解压 $CONFIG_PKG 到/etc/grafana/provisioning/dashboards/"
tar --strip-components 4 -C /etc/grafana/provisioning/dashboards/ -xvf "$CONFIG_PKG" grafana/conf/provisioning/dashboards/
chown grafana.grafana -R /etc/grafana/provisioning/

# 解压覆盖selfmonitor的dashboards等配置
systemctl daemon-reload
systemctl enable --now grafana-server
systemctl enable --now prometheus

# check status
systemctl status grafana-server prometheus