#!/usr/bin/env bash

source $HOME/.bash_profile
source $HOME/.bashrc

if [ ! -d "$CTRL_DIR" -o -z "$CTRL_DIR" ];then
    echo "crontrol dir not exists"
    exit
fi

source $CTRL_DIR/utils.fc

##set global init
CONFIG_FILE=$1
PRODUCT_NAME=$2
dbtype="mongodb"
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
                charset)charset=$value;;
                productname)productname=$value;;
                ignoredblist)ignoredblist=$value;;
                user)user=$value;;
                port)port=$value;;
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
     
    for f in $cmdpath/mongo  $cmdpath/mongodump  $backupdir
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

check_mongodb_alive() {
    local cmd="db.stats().ok"
    log "$FUNCNAME begin"
    
    local ret=$($MONGO_CMD --eval "$cmd")
	local word_cnt=$(echo $ret|wc -w)
    if [ $word_cnt -ne 1 ]; then
        fail "mongodb can't connect"
    fi
    if [ $ret -ne 1 ]; then
        fail "mongodb can't connect"
    fi
    log "$FUNCNAME successful"
    return $ret
}

get_db_list() {
    log "$FUNCNAME begin"
	TMP_ALL_DATABASE=$($MONGO_CMD  <<EOF
rs.slaveOk();
show dbs;
EOF
)
	ALL_DATABASE=""
	for db in `echo $TMP_ALL_DATABASE`
	do
		tmp_db=$(echo $db | grep -v GB| grep -vi "^$")
		if [ ! -z $tmp_db ];then
			ALL_DATABASE="$ALL_DATABASE $tmp_db"
		fi
	done
	ALL_DATABASE=($(echo $ALL_DATABASE))

    
    if [ -n "$dblist" ];then
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
		DUMP_DBLIST=$(echo $DUMP_DBLIST)
    fi

    ###### DUMP_DBLIST is empty, added default db_infobase
    if [ -z "$DUMP_DBLIST" ]; then
        DUMP_DBLIST="admin"
    fi

    log "ignore db list:$ignoredblist"  
    log "need dump db list:$DUMP_DBLIST"
    log "$FUNCNAME end"
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


do_backup() {

    cd $backupdir

    #if [ -z "$DUMP_DBLIST" ];then
    #    fail "fatal error, nothing to dump, exit"
    #fi
    
    
    btime1=$(date +%s)
    ibtime1=`date +"%Y-%m-%d %H:%M:%S"` 
    log "$FUNCNAME begin"
    $MONGO_DUMP_CMD

    btime2=$(date +%s)
    ibtime2=`date +"%Y-%m-%d %H:%M:%S"`

	err_cnt=$(grep `date "+%Y-%m-%d"` $BAK_LOG_FILE_NAME| grep -Ei "error|fail"|wc -l)
    if [ $err_cnt -ne 0 ];then
        err_msg=$(cat $BAK_ERR_LOG_PATH| grep `date "+%Y-%m-%d"`|grep -Ei "error|fail")
        fail "$err_msg"
    fi

    
    log "tar file begin"
    tar zcf $BAK_TAR_FILE_NAME ${dbtype}_${CURRENT_TIME}
    if [ $? -ne 0 ]; then
        warn "tar file error"
    else 
        rm -rf $TMP_BACKUP_DIR
        log "rm $TMP_BACKUP_DIR tmp directory"
    fi
    log "tar file end"

    log "$FUNCNAME dump end"
}

do_split_file () {
    max_size=$((8 * 1024 * 1024 * 1024))
    #max_size=10240 #test 10K
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
    backup_type="mongodump"
    dbtype=$dbtype
    backupdb_list="$DUMP_DBLIST"

}

cd $BACKUP_DIR
#####all program start######

###step0 get dbbackup.conf
read_ini_conf $PRODUCT_NAME

##step1 server init
#get server init
CURRENT_TIME=$(date "+%Y%m%d%H%M%S")
TMP_BACKUP_DIR="$backupdir/${dbtype}_${CURRENT_TIME}"
[ ! -d $TMP_BACKUP_DIR ] && mkdir -p $TMP_BACKUP_DIR || :

# init back file name
BAK_LOG_FILE_NAME="$backupdir/logs/dbbackup.log"
BAK_ERR_LOG_PATH="$backupdir/logs/dbbackup_${dbtype}.err"
BAK_TAR_FILE_NAME="${dbtype}-${PRODUCT_NAME}-${host}-${port}-${CURRENT_TIME}.tar.gz"
BAK_SPLIT_FILE_PREFIX="${dbtype}-${PRODUCT_NAME}-${host}-${port}-${CURRENT_TIME}.split."



MONGO_BIN=$cmdpath/mongo
MONGO_DUMP_BIN=$cmdpath/mongodump
MONGO_CMD="$MONGO_BIN --host $host:$port -u $user -p $BK_MONGODB_ADMIN_PASSWORD --authenticationDatabase admin --quiet"
MONGO_DUMP_CMD="$MONGO_DUMP_BIN --host $host:$port -u $user -p $BK_MONGODB_ADMIN_PASSWORD --oplog --gzip --out $TMP_BACKUP_DIR"



##step2 precheck
pre_check 

##step3 mongodb ping
check_mongodb_alive

##step4 get db lists
get_db_list

##step5 delete old dbbackup file
delete_old_backup

##step5 check disk space left
check_diskspace
if [ $? -ne 0 ]; then
    fail "diskspace free not enough"
fi

###backup start
#
##step7 backup start
do_backup

##step8 split file
do_split_file

##get backup info
get_dbbackup_info

###generl sql/xml/js statement
#gen_xml "$ip" "$port" "$real_host" "$real_port" "$begin_time" "$end_time" "$file_list" "$file_size" "$BACKUP_DIR" "$app" "$backup_type" "$dbtype" "$backupdb_list"
#
gen_json "$ip" "$port" "$real_host" "$real_port" "$begin_time" "$end_time" "$file_list" "$file_size" "$BACKUP_DIR" "$app" "$backup_type" "$dbtype" "$backupdb_list"
