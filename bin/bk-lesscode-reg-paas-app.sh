#!/usr/bin/env bash

set -eu
source ${CTRL_DIR:-/data/install}/load_env.sh
export MYSQL_PWD=$BK_PAAS_MYSQL_PASSWORD

creater="蓝鲸智云"
name="可视化开发平台"
type="开发工具"
name_en="bk_lesscode"
logo="applogo/bk_lesscode.png"
app_code=$BK_LESSCODE_APP_CODE
app_token=$BK_LESSCODE_APP_SECRET
auth_token="$app_token"
external_url="$BK_LESSCODE_PUBLIC_URL"
cmd_mysql="mysql -h${BK_PAAS_MYSQL_HOST} -u${BK_PAAS_MYSQL_USER} -P $BK_PAAS_MYSQL_PORT open_paas"
type_id=$($cmd_mysql -e "select * from  paas_apptags;" | grep "$type" | awk '{print $1}')
introduction="蓝鲸智云可视化开发平台提供了前端页面在线可视化拖拽组装、配置编辑、源码生成、二次开发等能力。旨在帮助用户通过尽量少的手写代码的方式快速设计和开发 SaaS。"
introduction_en="BlueKing visual development platform, provides front-end page online visual drag-and-drop assembly, configuration editing, source code generation, secondary development and other capabilities."

if [ -z "$app_token" ]; then
    echo "无法获取app_token"
    exit 1
fi

if [ -z "$type_id" ]; then 
    echo "无法获取type id"
    exit 1
fi

echo "insert entry if not exist."
$cmd_mysql -e "select code from paas_app where code='$app_code';" | grep -q "$app_code" || {
    $cmd_mysql << EOF
INSERT INTO paas_app
(name,code,introduction,creater,state,is_already_test,is_already_online,first_test_time,first_online_time,language,auth_token,tags_id,deploy_token,is_use_celery,is_use_celery_beat,is_saas,logo,height,is_max,is_resize,is_setbar,use_count,width,external_url,is_default,is_sysapp,is_third,is_platform,is_lapp,is_display,open_mode,introduction_en,name_en,visiable_labels)
 VALUES (
"$name","$app_code","$introduction","$creater",$type_id,TRUE ,TRUE,NULL,NOW(),"Java","$app_token",$type_id,NULL,FALSE,FALSE,FALSE,"$logo",700,TRUE,TRUE,FALSE,0,1200,"$external_url",TRUE,FALSE,TRUE,TRUE,FALSE,TRUE,"new_tab",introduction_en,name_en,"") ;
EOF
}

echo "then update entry."
$cmd_mysql << EOF
UPDATE paas_app SET
name="$name",introduction="$introduction",
name_en="$name_en",introduction_en="$introduction_en",
creater="$creater",first_online_time=NOW(),
auth_token="$auth_token",logo="$logo",
height=700,width=1200,external_url="$external_url"
WHERE code="$app_code";
EOF

echo "show entry:"
$cmd_mysql -e "select code,name,name_en,external_url from paas_app where code='$app_code';"
