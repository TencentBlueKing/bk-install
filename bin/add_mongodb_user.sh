#!/usr/bin/env bash
# 用途：在已经运行的mongodb上，添加用户
# 参考文档：
#       1. https://docs.mongodb.com/manual/tutorial/create-users/

# 通用脚本框架变量
PROGRAM=$(basename "$0")
VERSION=1.0
EXITCODE=0

# 全局默认变量
DB=
DB_USER=
DB_PASS=
MONGODB_URL=

usage () {
    cat <<EOF
用法: 
    $PROGRAM [ -h --help -?  查看帮助 ]
            [ -d, --db              [必填] "授权的db名"
            [ -i, --url             [必填] "链接mongodb的url"
            [ -u, --username        [必填] "db的用户名"
            [ -p, --password        [必填] "db的密码"
            [ -v, --version         [可选] "查看脚本版本号" ]
EOF
}

usage_and_exit () {
    usage
    exit "$1"
}

log () {
    echo "$@"
}

error () {
    echo "$@" 1>&2
    usage_and_exit 1
}

fail () {
    echo "$@" 1>&2
    exit 1
}

warning () {
    echo "$@" 1>&2
    EXITCODE=$((EXITCODE + 1))
}

version () {
    echo "$PROGRAM version $VERSION"
}

# 解析命令行参数，长短混合模式
(( $# == 0 )) && usage_and_exit 1
while (( $# > 0 )); do 
    case "$1" in
        -d | --db)
            shift
            DB=$1
            ;;
        -i | --url )
            shift
            MONGODB_URL=$1
            ;;
        -u | --username)
            shift
            DB_USER=$1
            ;;
        -p | --password)
            shift
            DB_PASS=$1
            ;;
        --help | -h | '-?' )
            usage_and_exit 0
            ;;
        --version | -v | -V )
            version 
            exit 0
            ;;
        -*)
            error "不可识别的参数: $1"
            ;;
        *) 
            break
            ;;
    esac
    shift 
done 

if [[ -z "$MONGODB_URL" || -z "$DB" || -z "$DB_USER" || -z "$DB_PASS" ]]; then
    warning "参数不能为空，每个都是必填"
fi
if [[ $EXITCODE -ne 0 ]]; then
    usage_and_exit "$EXITCODE"
fi

# 判断用户是否存在

result=$(mongo "$MONGODB_URL" --quiet <<END
db.system.users.find({ user: "$DB_USER", db: "$DB"}).count();
END
)

if [[ "${result}" -gt 0 ]]; then
    echo "用户 $DB_USER 对于DB $DB 的授权已创建, 跳过创建mongodb用户操作."
    exit 0
fi

# 开始添加用户
mongo "$MONGODB_URL" <<END
use $DB
db.createUser( {user: "$DB_USER",pwd: "$DB_PASS",roles: [ { role: "readWrite", db: "$DB" } ]})
END
echo "创建mongodb用户 $DB_USER"