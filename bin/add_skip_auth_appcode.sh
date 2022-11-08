#!/usr/bin/env bash
# 用途：该脚本将用户传入的app_code写入到paas esb的免登录态表中。


if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <app_code> [<login-path-for-paas>]]"
    exit 1
fi

APP_CODE=$1
LOGIN_PATH=${2:-mysql-paas}     # mysql_config_editor配置的paas数据库实例

# check 
if ! mysql --login-path="$LOGIN_PATH" -D open_paas -e 'show tables' >/dev/null; then
    echo "open_paas database not exists."
    exit 1
fi

# 蓝鲸自己后台默认的app_code需要添加到esb的免登录态白名单中
wlist=$(mysql --login-path="$LOGIN_PATH" -D open_paas -sNe "select wlist from esb_function_controller where func_code = 'user_auth::skip_user_auth'")

if ! echo "$wlist" | grep -qw "$APP_CODE"; then
    if mysql --login-path="$LOGIN_PATH" -D open_paas -e "update esb_function_controller set wlist=concat(wlist, ',$APP_CODE') where func_code = 'user_auth::skip_user_auth'"; then
        echo "add $APP_CODE to esb skip_user_auth white list succeed"
    else
        echo "add $APP_CODE to esb skip_user_auth white list failed"
        exit 1
    fi
fi