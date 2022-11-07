#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

######初始化全备份######
#1. 默认备份在主库
#2. 备份开始时间:3-7点
#3. 本地备份目录/data/dbbak
#4. 默认备份字符集为utf8
#5. 备份暂时支持dbtype:mysql,mongodb
#6. APP_NAME值:bkee(企业版本),bkce(社区版本)
#7. 部署crontab
######################

######版本变更######
#1. 支持MySQL/Mongodb add 2019.2.26
#2. 支持Redis add 2019.2.27
#3. 优化去除pass选项 2019.2.27
#4. 添加Redis/Influxdb备份 2019.3.5
######################
source "$HOME/.bash_profile"
source "$HOME/.bashrc"

if [[ ! -d "$CTRL_DIR" ]] || [[ -z "$CTRL_DIR" ]]; then
    echo "crontrol dir not exists"
    exit
fi

source "$CTRL_DIR/utils.fc"
source /etc/blueking/env/local.env  # get LAN_IP
export BACKUP_DIR=$BK_PKG_SRC_PATH/backup/dbbak
export APP_NAME=$1
export dbtype=$2

init_dbbackup_conf () {

    if [[ $dbtype = "mysql" ]] || [[ $dbtype = "mongodb" ]]; then
    cat > "$BACKUP_DIR/dbbackup_${dbtype}.conf" <<EOF
[${APP_NAME}]
productname=${APP_NAME}
charset=utf8
cmdpath=/usr/bin
host=$HOST
port=$PORT
user=$USER
dataorgrant=all
role=master
backupdir=$BACKUP_DIR
dbtype=$dbtype
oldfileleftday=3
ignoredblist=$IGNOREDBLIST
EOF

    elif [[ $dbtype = "redis" ]];then
    cat > "$BACKUP_DIR/dbbackup_${dbtype}.conf" <<EOF
[${APP_NAME}]
productname=${APP_NAME}
cmdpath=/usr/bin
host=$HOST
port=$PORT
backupdir=$BACKUP_DIR
dbtype=$dbtype
oldfileleftday=3
EOF

    elif [[ $dbtype = "influxdb" ]];then
    cat > "$BACKUP_DIR/dbbackup_${dbtype}.conf" <<EOF
[${APP_NAME}]
productname=${APP_NAME}
cmdpath=/usr/bin
host=$HOST
user=$USER
port=$PORT
backupdir=$BACKUP_DIR
dbtype=$dbtype
oldfileleftday=3
EOF
    fi
}

init_dbbackup () {
    [ -d /data ] && mkdir -p "$BACKUP_DIR"/logs
    cp "$CTRL_DIR"/storage/dbbackup/dbbackup_main.sh "$BACKUP_DIR"
    cp "$CTRL_DIR"/storage/dbbackup/dbbackup_"${dbtype}".sh "$BACKUP_DIR"
    init_dbbackup_conf
    addcron_for_dbbackup "${dbtype}"
}

addcron_for_dbbackup () {
    local cron_file cron_content
    cron_file=$(mktemp /tmp/crontab_XXXXX)
    cron_content=$(crontab -l | tee "$cron_file")

    if [[ $cron_content =~ dbbackup_main\.sh ]];then
        warn "dbbackup_main.sh is in crontab"
        exit        
    else
        sed -i "/dbbackup_main.sh/d" "$cron_file"
        echo "adding crontab entry [1 3 * * * /bin/bash ${BACKUP_DIR}/dbbackup_main.sh $APP_NAME >/dev/null 2>&1]"
        echo "1 3 * * * /bin/bash ${BACKUP_DIR}/dbbackup_main.sh $APP_NAME >/dev/null 2>&1" >>"$cron_file"

        crontab < "$cron_file"
    fi

    rm -f "$cron_file"
}

removecron_for_dbbackup () {
    local cron_file cron_content
    cron_file=$(mktemp /tmp/crontab_XXXXX)
    cron_content=$(crontab -l | tee "$cron_file")

    sed -i "/dbbackup_${dbtype}.sh/d" "$cron_file"

    crontab < "$cron_file"
    rm -f "$cron_file"
}

if [[ "${dbtype}" = "mysql" ]];then
    #mysql 一些账号和端口，我们给默认值，如果有差异需要用户自己去修改
    HOST=$LAN_IP
    PORT=3306
    USER=root
    IGNOREDBLIST="information_schema mysql test db_infobase performance_schema sys"
elif [ "${dbtype}" = "mongodb" ];then
    HOST=$LAN_IP
    PORT=27017
    USER=root
    IGNOREDBLIST="test"
elif [ "${dbtype}" = "redis" ];then
    HOST=$LAN_IP
    PORT=6379
elif [ "${dbtype}" = "influxdb" ];then
    HOST=$LAN_IP
    USER=${BK_INFLUXDB_ADMIN_USER:-admin}
    PORT=8086
else
    echo "${dbtype} not support yet"
    exit 1
fi

##init local
init_dbbackup