#!/usr/bin/env bash

source $HOME/.bash_profile
source $HOME/.bashrc

if [ ! -d "$CTRL_DIR" -o -z "$CTRL_DIR" ];then
    echo "crontrol dir not exists"
    exit
fi

source $CTRL_DIR/utils.fc
##set global init
export CONFIG_FILE=$1
export PRODUCT_NAME=$2
export dbtype="mysql"

export BACKUP_DIR="$BK_PKG_SRC_PATH/backup/dbbak/"
export LOG_FILE="$BACKUP_DIR/logs/dbbackup.log"

print_log () {
    local current_time=$(date "+%Y%m%d-%H:%M:%S")
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
get_mysql_version () {
    local version=$($MYSQL_CMD -e "show variables like 'version'"  | awk '{if (NR == 2) print $2}')
    if [ $? -ne 0 ]; then
        fail "$FUNCNAME error"
    fi
    echo $version
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
                ignoredblist)ignoredblist=$value;;
                user)user=$value;;
                port)port=$value;;
                charset)charset=$value;;
                role)role=$value;;
                dataorgrant)dataorgrant=$value;;
                backupdir)backupdir=$value;;
                backupdblist)backupdblist=$value;;
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
    for var in cmdpath host productname  user oldfileleftday  backupdir
    do
        cmd="test -n \"\$$var\""
         eval $cmd
         if [ $? -ne 0 ];then
           err_msg="$var not set"
           fail "var \$$var is not set(null), or is empty" 
           break
         fi           
    done

    if [ -n "$dblist" -a -n "$ignoredblist" ];then
        print "ERROR" "var dblist and ignoredblist are all  seted value" 
        err_msg="dblist error"
        ret=1
    elif [ -n "$dblist" -a -n "$ignoredblist" ];then
        err_msg="dblist error"
        ret=1
    fi
     
    for f in $cmdpath/mysql  $cmdpath/mysqldump   $cmdpath/mysqladmin   $backupdir
    do
        if [ ! -x $f   ];then
            err_msg="fatal error, $f permission denied"
            ret=1 
        fi
    done
    if [ $ret -eq 1 ]; then
        fail "$err_msg":
    fi

    log "$FUNCNAME successful"
    return $ret
}

check_mysql_alive() {
    local sql="select 1+1"
    log "$FUNCNAME begin"
    
    local ret=$($MYSQL_CMD -Nse "$sql")
    if [ $ret -ne 2 ]; then
        fail "mysql can't connect"
    fi
    log "$FUNCNAME successful"
    return $ret
}

get_db_list() {
    log "$FUNCNAME begin"
    
    if [ -n "$dblist" ];then
        ALL_DATABASE=($($MYSQL_BIN $MYSQL_USER_PASS_SOCK -Be "show databases"  | sed '1d'))
        DUMP_DBLIST=""
        for DB in $ALL_DATABASE 
        do
            for PDB in $MysqlDbList
            do
                if [ $DB = $PDB ];then
                    DUMP_DBLIST="$DUMP_DBLIST $PDB"
                fi
            done
        done
    elif [ -n "$ignoredblist" ];then
        ALL_DATABASE=($($MYSQL_CMD -Nse "show databases"  | sed '1d'))
        log "all db list:${ALL_DATABASE[*]}"
        DUMP_DBLIST=""
        ALL_DATABASE_LENGTH=${#ALL_DATABASE[*]}
        for IDB in $ignoredblist
        do
            for ((id=0;id<$ALL_DATABASE_LENGTH;id++)) 
            do
                if [ "${ALL_DATABASE[$id]}" == "$IDB" ];then
                    unset ALL_DATABASE[$id]
                    break       
                fi
            done
        done
        DUMP_DBLIST="${ALL_DATABASE[*]}"
    fi

    ###### DUMP_DBLIST is empty, added default db_infobase
    if [ -z "$DUMP_DBLIST" ]; then
        DUMP_DBLIST="db_infobase"
    fi

    log "ignore db list:$ignoredblist"  
    log "need dump db list:$DUMP_DBLIST"
    log "$FUNCNAME end"
}

delete_old_backup() {
    log "$FUNCNAME begin"
    if  [ -z "$backupdir" ];then
        fail "backup dir empty string"
    fi      
   
    log "delete those files before $oldfileleftday days ago"
    for suffix in sql sql.tar.gz priv schema sql.split
    do 
        find "$backupdir" -maxdepth 1  -name "${dbtype}-${productname}*.${suffix}*" -mtime +"${oldfileleftday}" -follow | sed "s/^/\t/"
        find "$backupdir" -maxdepth 1  -name "${dbtype}-${productname}*.${suffix}*" -mtime +"${oldfileleftday}" -follow -exec rm -f {} \;
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

do_backup_grant_priv() {
    local sql="select user, host from mysql.user"
    log "$FUNCNAME begin"

    if [ "${MYSQLVERSION:0:1}"  == "3" ];then
        fail "fatal error, not support this version"
    fi
    
    btime1=$(date +%s)
    split=\`
    special=`$MYSQL_CMD -Nse "$sql" | grep "$split" |wc -l `
    if [ $special -eq 0 ];then
        split=\`
    else
        special=`$MYSQL_CMD -Nse "$sql" | grep -E "'" |wc -l `
        if [ $special -eq 0 ];then
            split=\'\'
        else
            warn "the username have special char"
        fi
    fi

    
    #mysql version >=5.7 need to create user
    if [ "${MYSQLVERSION:0:3}"  == "5.7" ] || [[ "${MYSQLVERSION:0:1}" == "8" ]]; then
        for crtuser in `$MYSQL_CMD -Nse "select concat('$split', user, '$split', '@', '$split', host, '$split') from mysql.user;"`
        do
            $MYSQL_CMD -Nse "show create user $crtuser;" | sed 's/$/;/g' 1>> $BAK_PRIV_FILE_PATH 2>&1
        done

    fi

    
    for sqluser in `$MYSQL_CMD -Nse "select concat('$split', user, '$split', '@', '$split', host, '$split') from mysql.user;"`
    do
        $MYSQL_CMD -Nse "show grants for $sqluser;" | sed 's/$/;/g' 1>> $BAK_PRIV_FILE_PATH 2>&1
    done
    btime2=$(date +%s)


    error_cnt=$(grep -Ei "ERROR|WARN|FAIL" $BAK_PRIV_FILE_PATH|wc -l)
    if [ $error_cnt -ne 0 ];then
        err_msg=$(grep -Ei "ERROR|WARN|FAIL" $BAK_PRIV_FILE_PATH)
        fail "$err_msg"
    fi

    log "$FUNCNAME dump priv end"

}

do_backup() {

    local opt_schema=""
    local opt_charset=""
    local opt_comm=""
    local opt_master_data=""

    cd $backupdir
    if [ "$dataorgrant" == "grant" ]; then
        log "don't need to dump schema and data,exit"
        exit
    elif [ "$dataorgrant" == "schema" ]; then
        opt_schema=" -d "
    else 
        opt_schema=""
    fi

    if [ "${MYSQLVERSION:0:1}"  == "5" -o "${MYSQLVERSION:0:1}"  == "8" ];then
        opt_charset=" --default-character-set=$charset"
        #opt_comm=" --skip-opt  --create-options --single-transaction --max-allowed-packet=1G -E -R -q --no-autocommit  --hex-blob"
        opt_comm=" --skip-opt  --create-options --single-transaction --max-allowed-packet=1G --net_buffer_length=10M -e -E -R -q --no-autocommit  --hex-blob"
    elif [ -z "${MYSQLVERSION:0:1}" ];then
        fail "fatal error, Cann't get the version"    
    else
        fail "fatal error, not support this version"   
    fi

    local LOGBIN=$($MYSQL_CMD -e "show variables like 'log_bin'"  | awk '{if (NR == 2) print $2}')


    if [ "$LOGBIN" == "ON" ]; then
        if [ "${MYSQLVERSION:0:1}" == "5" -o "${MYSQLVERSION:0:1}" == "8" ]; then
            if [ $role == "master" ]; then
                opt_master_data=" --master-data=2 "
            else 
                opt_master_data=" --dump-slave==2 "
            fi
        fi
    else
        log "$MYSQLVERSION $LOGBIN so master-data not set"
    fi

    if [ -z "$DUMP_DBLIST" ];then
        fail "fatal error, nothing to dump, exit"
    fi
    
    
    cmd_line="$MYSQL_DUMP_CMD  $opt_schema $opt_comm  $opt_charset $opt_master_data -B $DUMP_DBLIST"
    cmd_line_struct="$MYSQL_DUMP_CMD -d $opt_comm  $opt_charset $opt_master_data -B $DUMP_DBLIST"
    
    btime1=$(date +%s)
    ibtime1=`date +"%Y-%m-%d %H:%M:%S"` 
    log "$FUNCNAME begin"
    log "$cmd_line 2>$BAK_ERR_LOG_PATH >>$BAK_SQL_FILE_PATH"
    if [ "$dataorgrant" == "schema" ]; then
        $cmd_line_struct 2>$BAK_ERR_LOG_PATH >>$BAK_SCHEMA_FILE_PATH
    else 
        $cmd_line_struct 2>$BAK_ERR_LOG_PATH >>$BAK_SCHEMA_FILE_PATH
        $cmd_line 2>>$BAK_ERR_LOG_PATH |gzip -c >>$BAK_SQL_FILE_PATH
    fi

    btime2=$(date +%s)
    ibtime2=`date +"%Y-%m-%d %H:%M:%S"`

    if [  -s $BAK_ERR_LOG_PATH ];then
        err_msg=$(cat $BAK_ERR_LOG_PATH)
        fail "$err_msg"
    fi

    
    if [ "$dataorgrant" == "all" ]; then
        log "tar file begin"
        tar zcf $BAK_SQL_TAR_FILE_NAME $BAK_SQL_FILE_NAME
        if [ $? -ne 0 ]; then
            warn "tar file error"
        else 
            rm -rf $BAK_SQL_FILE_NAME
            log "rm $BAK_SQL_FILE_NAME file"
        fi
        log "tar file end"
    fi

    log "$FUNCNAME dump end"
}

do_split_file () {
    max_size=$((8 * 1024 * 1024 * 1024))
    #max_size=10240 #test 10K
    if [ "$dataorgrant" == "all" ]; then
        file_size=$(stat -c "%s" $BAK_SQL_TAR_FILE_NAME)
        if [ $file_size -ge $max_size ]; then
            log "need split tar file,begin"
            log "split command:split -b $max_size $BAK_SQL_TAR_FILE_NAME -d -a 3 $BAK_SPLIT_FILE_PREFIX"
            split -b $max_size $BAK_SQL_TAR_FILE_NAME -d -a 3 $BAK_SPLIT_FILE_PREFIX
            if [ $? -ne 0 ]; then
                fail "split tar file failed,please check"
            fi

            rm -rf $BAK_SQL_TAR_FILE_NAME
            log "split tar file successful"

            #file_cnt=$((($file_size/$max_size) + ($file_size % $max_size> 0)))
            file_cnt=$(($file_size/$max_size))
            file_list="$BAK_PRIV_FILE_NAME $BAK_SCHEMA_FILE_NAME"
            for num in `seq -f"%003g" 0 $file_cnt`
            do
                file_list="${file_list} ${BAK_SPLIT_FILE_PREFIX}${num}"
                file_list=$(echo $file_list|awk 'gsub(/^ *| *$/,"")')
            done

        else 
            log "don't need to split "
            file_list="$BAK_PRIV_FILE_NAME $BAK_SCHEMA_FILE_NAME $BAK_SQL_TAR_FILE_NAME"
        fi
    elif [ "$dataorgrant" == "schema" ]; then 
        file_size=$(stat -c "%s" $BAK_SCHEMA_FILE_NAME)
        log "don't need to split "
        file_list="$BAK_PRIV_FILE_NAME $BAK_SCHEMA_FILE_NAME"
    else 
        file_size=$(stat -c "%s" $BAK_PRIV_FILE_NAME)
        log "don't need to split "
        file_list="$BAK_PRIV_FILE_NAME"
    fi
    return 0
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
    backup_type="mysqldump"
    dbtype=$dbtype
    backupdb_list="$DUMP_DBLIST"

}

#####all program start######

cd $BACKUP_DIR
##step0 get dbbackup.conf
read_ini_conf $PRODUCT_NAME

##step1 server init
#get server init
MYSQL_BIN=$cmdpath/mysql   
MYSQL_ADMIN_BIN=$cmdpath/mysqladmin
MYSQL_DUMP_BIN=$cmdpath/mysqldump
export MYSQL_PWD=$BK_MYSQL_ADMIN_PASSWORD
MYSQL_CMD="$MYSQL_BIN -h$host -P$port -u$user --default-character-set=$charset"
MYSQL_DUMP_CMD="$MYSQL_DUMP_BIN -h$host -P$port -u$user"

#get mysql version
MYSQLVERSION=`echo $(get_mysql_version)`
log "mysql version = $MYSQLVERSION"

# init back file name
CURRENT_TIME=$(date "+%Y%m%d%H%M%S")

BAK_SQL_FILE_NAME="${dbtype}-${PRODUCT_NAME}-${host}-${port}-${CURRENT_TIME}.sql"
BAK_SQL_FILE_PATH="$backupdir/$BAK_SQL_FILE_NAME"

BAK_SCHEMA_FILE_NAME="${dbtype}-${PRODUCT_NAME}-${host}-${port}-${CURRENT_TIME}.schema"
BAK_SCHEMA_FILE_PATH="$backupdir/$BAK_SCHEMA_FILE_NAME"

BAK_LOG_FILE_NAME="$backupdir/logs/dbbackup.log"
BAK_ERR_LOG_PATH="$backupdir/logs/dbbackup_${dbtype}.err"

BAK_PRIV_FILE_NAME="${dbtype}-${PRODUCT_NAME}-${host}-${port}-${CURRENT_TIME}.priv"
BAK_PRIV_FILE_PATH="$backupdir/$BAK_PRIV_FILE_NAME"

BAK_SQL_TAR_FILE_NAME=${BAK_SQL_FILE_NAME}.tar.gz
BAK_SPLIT_FILE_PREFIX="${BAK_SQL_FILE_NAME}.split."


##step2 precheck
pre_check 

##step3 mysql ping
check_mysql_alive

##step4 get db lists
get_db_list

##step5 delete old dbbackup file
delete_old_backup

##step5 check disk space left
check_diskspace
if [ $? -ne 0 ]; then
    fail "diskspace free not enough"
fi

##backup start
#1. backup grant privileges
#2. backup data and schema

##step6 grant backup start
do_backup_grant_priv

##step7 backup start
do_backup

##step8 split file
do_split_file

##get backup info
get_dbbackup_info

##generl sql/xml/js statement
#gen_xml "$ip" "$port" "$real_host" "$real_port" "$begin_time" "$end_time" "$file_list" "$file_size" "$BACKUP_DIR" "$app" "$backup_type" "$dbtype" "$backupdb_list"

gen_json "$ip" "$port" "$real_host" "$real_port" "$begin_time" "$end_time" "$file_list" "$file_size" "$BACKUP_DIR" "$app" "$backup_type" "$dbtype" "$backupdb_list"
