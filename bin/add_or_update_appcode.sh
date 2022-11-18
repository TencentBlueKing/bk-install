#!/usr/bin/env bash
# 用途：该脚本将用户传入的app_code和app_token写入到paas相关库中。


if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <app_code> <app_secrete> [<app_description>]"
    exit 1
fi

APP_CODE=$1
APP_SECRETE=$2
APP_DESC=${3:-"$1"}
LOGIN_PATH=${4:-mysql-paas}     # mysql_config_editor配置的paas数据库实例
TIMESTAMP="$(date +%Y-%m-%d\ %H:%M:%S)"

# check 
if ! mysql --login-path=$LOGIN_PATH -D open_paas -e 'show tables' >/dev/null; then
    echo "open_paas database not exists."
    exit 1
fi

if [[ -n "$(mysql --login-path=$LOGIN_PATH -D open_paas -e "select * from esb_app_account where app_code = \"$APP_CODE\"" 2>/dev/null)" ]] ; then
    echo "$APP_CODE exist. update it"
else
    echo "$APP_CODE doesn't exist. add it"
fi

# 添加到esb_app_account表中，这时app_code和app_secrete才能使用。
if mysql --login-path=$LOGIN_PATH -D open_paas -e \
 "INSERT INTO esb_app_account (app_code, app_token, introduction, created_time) VALUES('$APP_CODE', '$APP_SECRETE', '$APP_DESC', '$TIMESTAMP') ON DUPLICATE KEY UPDATE app_token='$APP_SECRETE'"; then
    echo "add $APP_CODE succeed."
else
    echo "add $APP_CODE failed."
    exit 1
fi

# 蓝鲸自己后台默认的app_code需要添加到esb的免登录态白名单中
wlist=$(mysql --login-path=$LOGIN_PATH -D open_paas -sNe "select wlist from esb_function_controller where func_code = 'user_auth::skip_user_auth'")

if ! echo "$wlist" | grep -qw $APP_CODE; then
    if mysql --login-path=$LOGIN_PATH -D open_paas -e "update esb_function_controller set wlist=concat(wlist, ',$APP_CODE') where func_code = 'user_auth::skip_user_auth'"; then
        echo "add $APP_CODE to esb skip_user_auth white list succeed"
    else
        echo "add $APP_CODE to esb skip_user_auth white list failed"
        exit 1
    fi
fi