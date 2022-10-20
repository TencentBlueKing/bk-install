#!/usr/bin/env bash
# shellcheck disable=SC1090
# 封装渲染配置的逻辑，该脚本在任意机器执行，而不用必须在中控机

# 全局默认变量
SELF_DIR=$(dirname "$(readlink -f "$0")")

# 加载环境变量和函数
if [[ -r ${SELF_DIR}/../tools.sh ]]; then
    source "${SELF_DIR}/../tools.sh"
else
    echo "${SELF_DIR}/../tools.sh 不存在" >&2
    exit 1
fi

MODULE=$1
#根据传入的参数做一个固定的映射为正确的模块目录名
MODULE_DIR_NAME=$(map_module_name "$MODULE")
if ! [[ -d $BK_HOME/$MODULE_DIR_NAME ]]; then
    echo "$BK_HOME/$MODULE_DIR_NAME 目录不存在，请确认模块参数是否有误"
    exit 1
fi 
if ! [[ -d $BK_PKG_SRC_PATH/$MODULE_DIR_NAME ]]; then
    echo "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME 目录不存在，请确认模块参数是否有误"
    exit 1
fi
case $MODULE_DIR_NAME in 
    open_paas)   # 因为env的文件名是paas.env
        "$SELF_DIR"/render_tpl -u -m "open_paas" -p "$BK_HOME" \
            -E LAN_IP="$LAN_IP" -e "${SELF_DIR}/04-final/paas.env" \
            "$BK_PKG_SRC_PATH"/open_paas/support-files/templates/*
        ;;
    usermgr|bkiam|bkssm|bkmonitorv3|bklog)
        # 渲染配置
        "$SELF_DIR"/render_tpl -u -m "$MODULE_DIR_NAME" -p "$BK_HOME" \
            -E LAN_IP="$LAN_IP" -e "${SELF_DIR}/04-final/${MODULE}.env" \
            "$BK_PKG_SRC_PATH/$MODULE"/support-files/templates/*
        ;;
    bknodeman)
        # 渲染配置
        "$SELF_DIR"/render_tpl -u -m "$MODULE_DIR_NAME" -p "$BK_HOME" \
            -E LAN_IP="$LAN_IP" -E WAN_IP="$WAN_IP" -e "${SELF_DIR}/04-final/${MODULE}.env" \
            "$BK_PKG_SRC_PATH/$MODULE"/support-files/templates/*
        ;;
    
    gse)    # 因为需要多增加WAN_IP的渲染，且templates下的只需要渲染#etc#gse开头的模块
        "$SELF_DIR"/render_tpl -u -m "$MODULE_DIR_NAME" -p "$BK_HOME" \
            -E LAN_IP="$LAN_IP" -E WAN_IP="$WAN_IP" -e "${SELF_DIR}/04-final/${MODULE_DIR_NAME}.env" \
            "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME"/support-files/templates/#etc#gse#*
        ;;
    cmdb) # 只渲染server/conf下的配置
        "$SELF_DIR"/render_tpl -u -m "$MODULE_DIR_NAME" -p "$BK_HOME" \
            -E LAN_IP="$LAN_IP" -E WAN_IP="$WAN_IP" -e "${SELF_DIR}/04-final/${MODULE_DIR_NAME}.env" \
            "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME"/support-files/templates/server#conf#*
        ;;
    job) 
        "$SELF_DIR"/render_tpl -u -m "$MODULE_DIR_NAME" -p "$BK_HOME" \
            -E LAN_IP="$LAN_IP" -E WAN_IP="$WAN_IP" -e "${SELF_DIR}/04-final/${MODULE_DIR_NAME}.env" \
            "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME"/support-files/templates/*
        ;;
    fta)
        "$SELF_DIR"/render_tpl -u -m "$MODULE_DIR_NAME" -p "$BK_HOME" \
            -E LAN_IP="$LAN_IP" -E BK_BEANSTALK_IP_COMMA="$BK_BEANSTALK_IP_COMMA" \
            -e "${SELF_DIR}/04-final/${MODULE_DIR_NAME}.env" \
            "$BK_PKG_SRC_PATH/$MODULE_DIR_NAME"/support-files/templates/*
        ;;
    lesscode)
        "$SELF_DIR"/render_tpl -u -m "$MODULE_DIR_NAME" -p "$BK_HOME" \
            -e "$SELF_DIR/04-final/${MODULE_DIR_NAME}.env" \
            "$BK_PKG_SRC_PATH"/$MODULE_DIR_NAME/support-files/templates/*
        ;;
    *)
        echo "Usage: $0 <模块>" >&2
        exit 1
        ;;
esac