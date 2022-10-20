#!/usr/bin/env bash
# 用途： 安装蓝鲸的用户管理后台(usermgr/api)
 
# 安全模式
set -euo pipefail 

# 重置PATH
PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH 

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")
USERMGR_MODULE=api

# 模块安装后所在的上一级目录
PREFIX=/data/bkee

# 模块目录的上一级目录
MODULE_SRC_DIR=/data/src

# PYTHON目录
PYTHON_PATH=/opt/py36_e/bin/python3.6

# 默认安装所有子模块
MODULE=usermgr
RPM_DEP=(gcc)
ENV_FILE=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ --python-path     [可选] "指定创建virtualenv时的python二进制路径" ]
            [ -e, --env-file    [可选] "使用该配置文件来渲染" ]

            [ -s, --srcdir      [必选] "从该目录拷贝usermgr目录到--prefix指定的目录" ]
            [ -p, --prefix      [可选] "安装的目标路径，默认为/data/bkee" ]
            [ --log-dir         [可选] "日志目录,默认为$PREFIX/logs/usermgr" ]

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
        --python-path )
            shift
            PYTHON_PATH=$1
            ;;
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

LOG_DIR=${LOG_DIR:-$PREFIX/logs/usermgr}

# 参数合法性有效性校验，这些可以使用通用函数校验。
if ! [[ -d "$MODULE_SRC_DIR"/usermgr ]]; then
    warning "$MODULE_SRC_DIR/usermgr 不存在"
fi
if ! [[ $($PYTHON_PATH --version 2>&1) = *Python* ]]; then
    warning "$PYTHON_PATH 不是一个合法的python二进制"
fi
if ! [[ -r "$ENV_FILE" ]]; then
    warning "ENV_FILE: ($ENV_FILE) 不存在或者未指定"
fi
if (( EXITCODE > 0 )); then
    usage_and_exit "$EXITCODE"
fi


id -u blueking &>/dev/null || \
    { echo "<blueking> user has not been created, please check ./bin/update_bk_env.sh"; exit 1; } 

install -o blueking -g blueking -d "${LOG_DIR}"
install -o blueking -g blueking -m 755 -d /etc/blueking/env 
install -o blueking -g blueking -m 755 -d "$PREFIX/$MODULE"
install -o blueking -g blueking -m 755 -d "$PREFIX/public/$MODULE"
install -o blueking -g blueking -m 755 -d /var/run/usermgr

# 配置/var/run临时目录重启后继续生效
cat > /etc/tmpfiles.d/usermgr.conf <<EOF
D /var/run/usermgr 0755 blueking blueking
EOF

# 拷贝模块目录到$PREFIX
rsync -a --delete "${MODULE_SRC_DIR}/$MODULE/" "$PREFIX/$MODULE/"

case $USERMGR_MODULE in 
    api) 
        # 安装rpm依赖包，如果不存在
        if ! rpm -q "${RPM_DEP[@]}" >/dev/null; then
            yum -y install "${RPM_DEP[@]}"
        fi
       # 安装虚拟环境和依赖包
        "${SELF_DIR}"/install_py_venv_pkgs.sh -e -p "$PYTHON_PATH" \
            -n "${MODULE}-${USERMGR_MODULE}" \
            -w "${PREFIX}/.envs" -a "$PREFIX/$MODULE/${USERMGR_MODULE}" \
            -s "$PREFIX/$MODULE/support-files/pkgs" \
            -r "$PREFIX/$MODULE/${USERMGR_MODULE}/requirements.txt"
        if [[ "$PYTHON_PATH" = *_e* ]]; then
            # 拷贝加密解释器 //todo
            cp -a "${PYTHON_PATH}"_e $PREFIX/.envs/${MODULE}-${USERMGR_MODULE}/bin/python
        fi
        # 渲染配置
        "$SELF_DIR"/render_tpl -u -m "$MODULE" -p "$PREFIX" \
                -e "$ENV_FILE" \
                "$MODULE_SRC_DIR"/$MODULE/support-files/templates/*api*
        
        (
            set +u
            export BK_FILE_PATH="$PREFIX"/usermgr/cert/saas_priv.txt 
            export WORKON_HOME=$PREFIX/.envs
            VIRTUALENVWRAPPER_PYTHON="$PYTHON_PATH"
            source "${PYTHON_PATH%/*}/virtualenvwrapper.sh"
            workon "${MODULE}-${USERMGR_MODULE}" && \
            export DJANGO_SETTINGS_MODULE=config.ee.prod && \
            python manage.py migrate
        )

        chown blueking.blueking -R "$PREFIX/$MODULE" "$LOG_DIR"
    
        # 生成systemd的配置
        cat > /usr/lib/systemd/system/bk-usermgr.service <<EOF
[Unit]
Description=Blueking Usermgr backend Supervisor daemon
After=network-online.target
PartOf=blueking.target

[Service]
User=blueking
Group=blueking
Type=forking
Environment=BK_FILE_PATH=$PREFIX/usermgr/cert/saas_priv.txt 
ExecStart=/opt/py36/bin/supervisord -c $PREFIX/etc/supervisor-usermgr-api.conf
ExecStop=/opt/py36/bin/supervisorctl -c $PREFIX/etc/supervisor-usermgr-api.conf shutdown
ExecReload=/opt/py36/bin/supervisorctl -c $PREFIX/etc/supervisor-usermgr-api.conf reload
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target blueking.target
EOF
        systemctl daemon-reload
        ;;
esac

if ! systemctl is-enabled "bk-usermgr" &>/dev/null; then
    systemctl enable --now bk-usermgr
else
    systemctl start bk-usermgr
fi

# 校验是否成功
sleep 1
systemctl status bk-usermgr