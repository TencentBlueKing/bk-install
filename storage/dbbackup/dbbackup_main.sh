#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

source $HOME/.bash_profile
source $HOME/.bashrc

if [ ! -d "$CTRL_DIR" -o -z "$CTRL_DIR" ];then
    echo "crontrol dir not exists"
    exit
fi

source $CTRL_DIR/utils.fc

backup_dir="$BK_PKG_SRC_PATH/backup/dbbak"
logfile=$backup_dir/logs/dbbackup.log
APP_NAME=$1

if [ -e $logfile ]
then
        SIZE=$(stat $logfile -c %s);

        if [ $SIZE -gt 100000000 ]
        then
                mv $logfile $logfile.old
        fi
fi
echo "begin mutli dbbackup" >>$logfile
for conf_file in "$backup_dir"/dbbackup*.conf
do
    echo "now doing dbbackup for config file:$conf_file"
    if [[ $conf_file =~ "mysql" ]];then
        backup_cmd="$backup_dir/dbbackup_mysql.sh"
    elif [[ $conf_file =~ "mongodb" ]];then
        backup_cmd="$backup_dir/dbbackup_mongodb.sh"
    elif [[ $conf_file =~ "redis" ]];then
        backup_cmd="$backup_dir/dbbackup_redis.sh"
    elif [[ $conf_file =~ "influxdb" ]];then
        backup_cmd="$backup_dir/dbbackup_influxdb.sh"
    else 
        echo "$conf_file dbtype not support yet"
        exit 1
    fi
    /bin/bash $backup_cmd $conf_file $APP_NAME >/dev/null 2>&1
done
