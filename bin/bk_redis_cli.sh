#!/usr/bin/env bash

if ! command -v redis-cli &>/dev/null; then
    echo "no redis-cli command"
    exit 1
fi

if [[ -f $CTRL_DIR/load_env.sh ]]; then
    source "$CTRL_DIR/load_env.sh"
else
    echo "no $CTRL_DIR/load_env.sh found"
    exit 1
fi

usage () {
    echo "Usage: $0 -n <module> -c '<redis command>'"
    exit 2
}

get_redis_cli_cmdline () {
    local module=$1
    local redis redis_mode redis_host redis_port redis_password 
    local redis_sentinel_addr redis_sentinel_host redis_sentinel_port redis_sentinel_master_name
    local tmp

    case $module in 
        paas)
            # paas redis always standlone mode
            echo "redis-cli -h $BK_PAAS_REDIS_HOST -p $BK_PAAS_REDIS_PORT -a $BK_PAAS_REDIS_PASSWORD"
            ;;
        gse)
            # gse redis always standalone mode and deploy with gse-dba process
            echo "redis-cli -h $BK_GSE_IP0 -p $BK_GSE_REDIS_PORT -a $BK_GSE_REDIS_PASSWORD"
            ;;
        cmdb)
            if [[ -z $BK_CMDB_REDIS_MASTER_NAME ]]; then
                # redis standalone mode
                echo "redis-cli -h $BK_CMDB_REDIS_SENTINEL_HOST -p $BK_CMDB_REDIS_SENTINEL_PORT -a $BK_CMDB_REDIS_PASSWORD"
            else
                # redis sentinel mode
                redis=$(redis-cli -h "$BK_CMDB_REDIS_SENTINEL_HOST" -p "$BK_CMDB_REDIS_SENTINEL_PORT" sentinel get-master-addr-by-name mymaster | xargs)
                echo "redis-cli -h ${redis% *} -p ${redis#* } -a $BK_CMDB_REDIS_PASSWORD"
            fi
            ;;
        iam|ssm|monitor)
            # redis密码是通用的key
            tmp=BK_${module^^}_REDIS_PASSWORD
            redis_password=${!tmp}

            tmp=BK_${module^^}_REDIS_MODE
            if [[ ${!tmp} = "standalone" ]]; then
                tmp=BK_${module^^}_REDIS_HOST
                redis_host=${!tmp}

                tmp=BK_${module^^}_REDIS_PORT
                redis_port=${!tmp}
            elif [[ ${!tmp} = "sentinel" ]]; then
                tmp=BK_${module^^}_REDIS_SENTINEL_ADDR
                redis_sentinel_addr=${!tmp}
                redis_sentinel_host=${redis_sentinel_addr%:*}
                redis_sentinel_port=${redis_sentinel_addr#*:}
                tmp=BK_${module^^}_REDIS_SENTINEL_MASTER_NAME
                redis_sentinel_master_name=${!tmp}

                redis=$(redis-cli -h "$redis_sentinel_host" -p "$redis_sentinel_port" sentinel get-master-addr-by-name $redis_sentinel_master_name | xargs)
                redis_host=${redis% *}
                redis_port=${redis#* }
            else
                echo "not supported ${!tmp} mode in module <$module>"
                exit 2
            fi
            echo "redis-cli -h $redis_host -p $redis_port -a $redis_password"
            ;;
        *)
            echo "$module is not supported yet."
            exit 1
            ;;
    esac
}

while getopts ':n:c:' arg; do 
    case $arg in
        n) MODULE="$OPTARG" ;;
        c) COMMAND="$OPTARG";;
        *) usage ;;
    esac
done
shift $((OPTIND-1))

if [[ -n $MODULE && -n "$COMMAND" ]]; then
    echo "run command <$COMMAND> against <$MODULE>'s Redis instance"
elif [[ -n "$MODULE" && -z "$COMMAND" ]]; then
    echo "connect to <$MODULE>'s Redis instance interactive mode"
else
    usage
fi

REDIS_CLI_STR=$(get_redis_cli_cmdline "$MODULE")
echo "<$MODULE>'s Redis instance info: <$REDIS_CLI_STR>"

if [[ -z "$COMMAND" ]]; then
    eval "$REDIS_CLI_STR"
else
    eval "$REDIS_CLI_STR" "$COMMAND"
fi