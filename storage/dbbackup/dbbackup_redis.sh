#!/usr/bin/env bash

source $HOME/.bash_profile
source $HOME/.bashrc

if [ ! -d "$CTRL_DIR" -o -z "$CTRL_DIR" ];then
    echo "crontrol dir not exists"
    exit
fi

source $CTRL_DIR/utils.fc

export BACKUP_DIR="$BK_PKG_SRC_PATH/backup/dbbak/"
export LOG_FILE="$BACKUP_DIR/logs/dbbackup.log"
##set global init
CONFIG_FILE=$1
PRODUCT_NAME=$2

print_log () {
    local current_time=`date "+%Y%m%d-%H:%M:%S"`
    local warn_type="$1"
    local warn_content="$2"
    if [ -z $warn_type ]; then 
        echo "$current_time $0 $warn_content"
    elif [ $warn_type = "ERROR" ]; then
        ## ERROR display red color font
        echo -e "\033[031;1m$current_time $0 $warn_type $BASH_LINENO: $warn_content\033[0m"
        exit 1
    elif [ $warn_type = "WARN" ]; then
        ## WARN display yellow color font
        echo -e "\033[033;1m$current_time $0 $warn_type $BASH_LINENO: $warn_content\033[0m"
    else 
        echo -e "$current_time $0 $warn_type: $warn_content"
    fi
}

## gen json format
gen_json () {
cat >${backupdir}/dbbackup_info_${dbtype}.json <<EOF
{
    "ip": "$1",
    "port": $2,
    "real_host": "$3",
    "real_port": $4,
    "begin_time": "$5",
    "end_time": "$6",
    "file_list":"$7",
    "file_size": $8,
    "backup_dir": "$9",
    "app": "${10}",
    "backup_type": "${11}",
    "dbtype": "${12}",
    "backup_dblist": "${13}"
}
EOF


}

## gen xml format
gen_xml () {
cat >${backupdir}/dbbackup_info.xml <<EOF
<?xml version='1.0' encoding="iso-8859-1" ?>
<xml_data name="dbbackup_info_other">
  <xml_row>
    <xml_field name="ip">$1</xml_field>
    <xml_field name="port">$2</xml_field>
    <xml_field name="real_host">$3</xml_field>
    <xml_field name="real_port">$4</xml_field>
    <xml_field name="begin_time">$5</xml_field>
    <xml_field name="end_time">$6</xml_field>
    <xml_field name="file_list">$7</xml_field>
    <xml_field name="file_size">$8</xml_field>
    <xml_field name="backup_dir">$9</xml_field>
    <xml_field name="app">${10}</xml_field>
    <xml_field name="backup_type">${11}</xml_field>
    <xml_field name="dbtype">${12}</xml_field>
    <xml_field name="backup_dblist">${13}</xml_field>
  </xml_row>
</xml_data>
EOF
}

read_ini_conf () {
    local segname=''
    local ret=1 
    log "$FUNCNAME begin"
    if [ ! -f "$CONFIG_FILE" ];then
        fail "config_file $CONFIG_FILE not find,please check"
    fi

    while read line
    do
        t_line=$(echo $line | sed -e "s/^[ \t]*//" -e "s/[ \t]*$//" -e "s/[ \t]*=[ \t]*/=/" ) 
        if [ -z "$t_line" ];then
            log "config_file exists empty line"
            continue    
        elif [ ${t_line:0:1} = "#"  ];then
            log "nouse parameter:$t_line"
            continue    
        elif [ ${t_line:0:1} = "[" ];then
            if [ -n "$segname"  ];then
                fail "duplicate segname defined:$segname, exit"
            fi    
            segname=$t_line
            continue
        fi

        if  [ $segname = "[$1]" ];then
            ret=0
            local key=${t_line%%=*}
            local value=${t_line#*=}    
            log "get key value:$key = $value"

            if [ -z "$key"  ];then
                fail "$segname, empty key found"
            fi

            case $key in 
                cmdpath)cmdpath=$value;;
                host)host=$value;;
                productname)productname=$value;;
                port)port=$value;;
                backupdir)backupdir=$value;;
                dbtype)dbtype=$value;;
                oldfileleftday)oldfileleftday=$value;;
                *) warn "no use key $segname:$key found";;
            esac
        fi
    done <  $CONFIG_FILE 
    [ -d ${backupdir} ] || backupdir="/data/dbbak"
    log "$FUNCNAME successful"
    return $ret
}

pre_check () {
    log "$FUNCNAME begin"
    local ret=0
    for var in cmdpath host productname  oldfileleftday  backupdir ROLE
    do
        cmd="test -n \"\$$var\""
         eval $cmd
         if [ $? -ne 0 ];then
           err_msg="$var not set"
           fail "var \$$var is not set(null), or is empty" 
           break
         fi           
    done

     
    for f in $cmdpath/redis-cli  $backupdir
    do
        if [ ! -x $f   ];then
            err_msg="fatal error, $f permission denied"
            ret=1 
        fi
    done
    if [ $ret -eq 1 ]; then
        fail "$err_msg"
    fi

    log "$FUNCNAME successful"
    return $ret
}

check_redis_alive() {
    local cmd="ping"
    log "$FUNCNAME begin"
    
    local ret=$($REDIS_CMD -r 3 $cmd 2>/dev/null)
    if [[ $ret =~ "PONG" ]]; then
        log "$FUNCNAME successful"
    else 
        fail "$FUNCNAME failed"
    fi
}

delete_old_backup () {
    log "$FUNCNAME begin"
    if  [ -z "$backupdir" ];then
        fail "backup dir empty string"
    fi      
   
    log "delete those files before $oldfileleftday days ago"
    for suffix in tar.gz split
    do 
        find "$backupdir" -maxdepth 1  -name "${dbtype}-${productname}*.${suffix}" -mtime +"${oldfileleftday}" -follow | sed "s/^/\t/"
        find "$backupdir" -maxdepth 1  -name "${dbtype}-${productname}*.${suffix}" -mtime +"${oldfileleftday}" -follow -exec rm -f {} \;
    done 
    log "$FUNCNAME end"
}

check_diskspace() {
    log "$FUNCNAME begin"
    #get old file size
    local jq_cmd="/usr/bin/jq"
    if [ -e "$jq_cmd" ]; then
        last_file_size=$(cat $backupdir/dbbackup_info_${dbtype}.json |$jq_cmd '.file_size')
    else
        last_file_size=$(cat $backupdir/dbbackup_info_${dbtype}.json | grep 'file_size' | awk '{print $2}' | awk -F',' '{print $1}')
    fi

    if [ -z "$last_file_size" ];then
        last_file_size=1
    else
        last_file_size=$(($last_file_size/1024))
    fi  

   
    last_file_size_3times=$(($last_file_size/1024 * 3))
        
    leftarr=$(df -k $backupdir  | sed '1d')
    leftarr=($(echo $leftarr))
    log "last back file size:${last_file_size}k,disk freespace:${leftarr[3]}k" 
 
    if [ -n ${leftarr[3]}  -a ${leftarr[3]} -lt $last_file_size_3times ];then
        return 1
        fail "disk freespace only ${leftarr[3]}k left"
    fi
    log "$FUNCNAME disk space check ok" 
    return 0
}

do_bgsave () {
    local cmd="bgsave"
    local info_cmd="info Persistence"

    log "$FUNCNAME start"
    local o=$($REDIS_CMD $cmd 2>/dev/null)
    log "$FUNCNAME $o"

    sleep 5 
    #check bgsave is done
    is_done=0
    while [ $is_done -le 0 ]; do
        o=$($REDIS_CMD $info_cmd 2>/dev/null|grep -Ei "rdb_bgsave_in_progress")
        if [[ $o =~ "rdb_bgsave_in_progress:0" ]];then
            log "$FUNCNAME successful"
            is_done=1
            break
        fi
        log "$FUNCNAME waiting for  bgsave done"
        sleep 10
    done
    used_sec=$($REDIS_CMD $info_cmd 2>/dev/null|grep -Ei "rdb_last_bgsave_time_sec"|awk -F':' '{print $2}'|sed 's/\r//g')
    if  [ "$used_sec" = "0" ];then
        used_sec=$((used_sec +1))
    fi
    log "$FUNCNAME done use $used_sec seconds"
}

backup_file() {
    local dir_cmd="config get dir"
    local dbfilename_cmd="config get dbfilename"
    local dir=$($REDIS_CMD --raw $dir_cmd 2>/dev/null|grep -v dir|sed 's/\r//g')
    local dbfilename=$($REDIS_CMD --raw $dbfilename_cmd 2>/dev/null|grep -v dbfilename|sed 's/\r//g')
    if [ -f $BAK_TAR_FILE_NAME ];then
        nassert "$FUNCNAME $BAK_TAR_FILE_NAME is already exits,skip backup"        
    fi
    log "$FUNCNAME tar file start" 
    tar -zcvf $BAK_TAR_FILE_NAME -C $dir $dbfilename

    if [ ! -f $BAK_TAR_FILE_NAME ];then
        nassert "$FUNCNAME tar $BAK_TAR_FILE_NAME failed"
    fi
    log "$FUNCNAME tar file successful" 
}

do_backup() {

    cd $backupdir
    log "$FUNCNAME begin"

    btime1=$(date +%s)
    ibtime1=`date +"%Y-%m-%d %H:%M:%S"`
    if [ "$ROLE" = "master" -a "$SLAVE_CNT" != "0" ];then
        warn "$FUNCNAME role:$ROLE and have $SLAVE_CNT slaves,skip backup"
        exit
    else 
        if [ "$ROLE" = "slave" ];then
            MASTER_LS=$($REDIS_CMD $info_cmd 2>/dev/null | grep -Ei "master_link_status"|awk -F':' '{print $2}'|sed 's/\r//g')
            if [ "$MASTER_LS" = "down" ];then
                fail "$FUNCNAME slave not connect to master,check"
            fi

        fi
        btime1=$(date +%s)
        ibtime1=`date +"%Y-%m-%d %H:%M:%S"`

        do_bgsave

        btime2=$(date +%s)
        ibtime2=`date +"%Y-%m-%d %H:%M:%S"`

        backup_file
    fi


    log "$FUNCNAME end"
}

do_split_file () {
    max_size=$((8 * 1024 * 1024 * 1024))
    #max_size=102400 #test 10K
    file_size=$(stat -c "%s" $BAK_TAR_FILE_NAME)
    if [ $file_size -ge $max_size ]; then
        log "need split tar file,begin"
        log "split command:split -b $max_size $BAK_TAR_FILE_NAME -d -a 3 $BAK_SPLIT_FILE_PREFIX"
        split -b $max_size $BAK_TAR_FILE_NAME -d -a 3 $BAK_SPLIT_FILE_PREFIX
        if [ $? -ne 0 ]; then
            fail "split tar file failed,please check"
        fi

        rm -rf $BAK_TAR_FILE_NAME
        log "split tar file successful"

        file_cnt=$(($file_size/$max_size))
        for num in `seq -f"%003g" 0 $file_cnt`
        do
            file_list="${file_list} ${BAK_SPLIT_FILE_PREFIX}${num}"
            file_list=$(echo $file_list|awk 'gsub(/^ *| *$/,"")')
        done

    else 
        log "don't need to split "
        file_list="$BAK_TAR_FILE_NAME"
    fi
    return 0
}

get_redis_repl_info () {
    local cmd="info replication"
    local master_info=$($REDIS_CMD $cmd 2>/dev/null | grep -Ei "role"|awk -F':' '{print $2}')
    local slave_info=$($REDIS_CMD $cmd 2>/dev/null | grep -Ei "connected_slaves"|awk -F':' '{print $2}')
    echo "$master_info $slave_info"
}

get_dbbackup_info () {
    
    ip=$host
    port=$port
    real_host=$host
    real_port=$port
    begin_time="$ibtime1"
    end_time="$ibtime2"
    file_list=$file_list
    file_size=$file_size
    backup_dir=$backupdir
    app=$productname
    backup_type="bgsave"
    dbtype=$dbtype
    backupdb_list="db0"

}

cd $BACKUP_DIR
#####all program start######

###step0 get dbbackup.conf
read_ini_conf $PRODUCT_NAME

##step1 server init
#get server init
CURRENT_TIME=$(date "+%Y%m%d%H%M%S")

# init back file name
BAK_LOG_FILE_NAME="$backupdir/logs/dbbackup.log"
BAK_ERR_LOG_PATH="$backupdir/logs/dbbackup_${dbtype}.err"
BAK_TAR_FILE_NAME="${dbtype}-${PRODUCT_NAME}-${host}-${port}-${CURRENT_TIME}.tar.gz"
BAK_SPLIT_FILE_PREFIX="${dbtype}-${PRODUCT_NAME}-${host}-${port}-${CURRENT_TIME}.split."



REDIS_BIN="$cmdpath/redis-cli"
REDIS_CMD="$REDIS_BIN -h $host -p $port -a $BK_REDIS_ADMIN_PASSWORD" 

info_cmd="info"
ROLE=$($REDIS_CMD $info_cmd 2>/dev/null | grep -Ei "role"|awk -F':' '{print $2}'|sed 's/\r//g')
SLAVE_CNT=$($REDIS_CMD $info_cmd 2>/dev/null | grep -Ei "connected_slaves"|awk -F':' '{print $2}'|sed 's/\r//g')
IS_AOF_ENABLED=$($REDIS_CMD $info_cmd 2>/dev/null | grep -Ei "aof_enabled"|awk -F':' '{print $2}'|sed 's/\r//g')



##step2 precheck
pre_check 

##step3 redis ping
check_redis_alive

##step5 delete old dbbackup file
delete_old_backup

##step5 check disk space left
check_diskspace
if [ $? -ne 0 ]; then
    fail "diskspace free not enough"
fi

#do dbbackup
do_backup

##step8 split file
do_split_file

##get backup info
get_dbbackup_info

####generl sql/xml/js statement
##gen_xml "$ip" "$port" "$real_host" "$real_port" "$begin_time" "$end_time" "$file_list" "$file_size" "$BACKUP_DIR" "$app" "$backup_type" "$dbtype" "$backupdb_list"
##
gen_json "$ip" "$port" "$real_host" "$real_port" "$begin_time" "$end_time" "$file_list" "$file_size" "$BACKUP_DIR" "$app" "$backup_type" "$dbtype" "$backupdb_list"
