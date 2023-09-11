#!/usr/bin/env bash

export LC_ALL=C LANG=C
SELF_DIR=$(dirname $(readlink -f $0))
if [[ -z "$BK_PKG_SRC_PATH" ]]; then 
    BK_PKG_SRC_PATH=$(readlink -f ${SELF_DIR}/../../src)
fi

if [[ -s $SELF_DIR/../bin/02-dynamic/hosts.env ]]; then 
    . $SELF_DIR/../bin/02-dynamic/hosts.env 
else
    if ! [[ -s ${SELF_DIR}/../install.config ]]; then
        echo "请先配置 install.config 文件，并生成 02-dynamic/hosts.env 文件"
        exit 1
    else
        # generate hosts.env and source it
        ${SELF_DIR}/../bin/bk-install-config-parser.awk ${SELF_DIR}/../install.config >$SELF_DIR/../bin/02-dynamic/hosts.env
        . $SELF_DIR/../bin/02-dynamic/hosts.env 
    fi
fi

check_ssh_nopass () {
    for ip in "${ALL_IP[@]}"; do
       echo -ne "$ip\t"
       if ssh -o 'PreferredAuthentications=publickey' -o 'StrictHostKeyChecking=no' "$ip" "true" 2>/dev/null; then
           echo "publickey Auth OK"
       else
           echo "publickey Auth FAILED, please configure no-pass login first."
           return 1
       fi
    done
    return 0
}

check_hostname_uniq () {
    local dup_hostname
    dup_hostname=$(for ip in "${ALL_IP[@]}"; do 
        ssh $ip hostname 
    done | sort | uniq -c | awk '$1 > 1')
    if [[ -z "$dup_hostname" ]]; then
        echo "all hosts has uniq hostname"
    else
        echo "some hosts has duplicate hostname, please modify them first."
        echo "$dup_hostname" | xargs -n2 printf "        there are %d hosts has the same hostname <%s>\n"
        return 1
    fi
}

get_license_mac () {
    for ip in "${BK_LICENSE_IP[@]}"; do
       ssh "$ip" 'cat /sys/class/net/*/address'
    done
}

check_cert_mac () {
    local cert_file=${BK_PKG_SRC_PATH}/cert/platform.cert
    if [[ ! -f "$cert_file" ]]; then
       echo "cert not exists"
       return 1
    fi
    local detail=$(openssl x509 -noout -text -in "$cert_file" 2>/dev/null)
    local cnt=$(grep -cFf <(get_license_mac) <(sed -n '/Subject Alternative Name:/{n;p}' <<<"$detail" | grep -Po '\b([a-z0-9]{2}:){5}[a-z0-9]{2}\b' ))
    [[ $cnt -eq ${#BK_LICENSE_IP[@]} ]]
}

check_password () {
    # MYSQL密码不能有'#&'号
    :
}

check_domain () {
    local err_domain=""
    local err_fqdn=""
    source ${SELF_DIR}/../bin/default/global.env 
    source ${SELF_DIR}/../load_env.sh

    # BK_DOMAIN 不能是顶级域名，没有\.字符时
    if ! [[ $BK_DOMAIN =~ \. ]]; then
        echo "BK_DOMAIN不应该是顶级域名，请配置二级域名或者以上"
        return 1
    fi

    # FQDN等包含合法字符
    for d in BK_DOMAIN BK_PAAS_PUBLIC_ADDR BK_JOB_PUBLIC_ADDR BK_CMDB_PUBLIC_ADDR; do
        if ! [[ $(eval echo "\$$d") =~  ^[A-Za-z0-9.-]+\.[a-z]+(:[0-9]+)?$ ]]; then
            err_domain="$err_domain $d"
        fi
    done

    # FQDN 必须基于BK_DOMAIN
    for d in BK_PAAS_PUBLIC_ADDR BK_JOB_PUBLIC_ADDR BK_CMDB_PUBLIC_ADDR; do
        if ! [[ $(eval echo "\$$d") =~ $BK_DOMAIN(:[0-9]+)?$ ]]; then
            err_fqdn="$err_fqdn $d" 
        fi
    done

    if [[ -z "$err_domain" && -z "$err_fqdn" ]]; then
        return 0
    else
        [[ -n "$err_domain" ]] && echo "以下域名包含非法字符：$err_domain"
        [[ -n "$err_fqdn" ]] && echo "以下PUBLIC_ADDR没有以$BK_DOMAIN结尾：$err_fqdn"
        return 1
    fi
}

check_src_dir () { 
    if ! [[ -d $BK_PKG_SRC_PATH/python ]]; then
        echo "no python directory under $BK_PKG_SRC_PATH. please extract it first."
        return 1
    fi
    if ! [[ -d $BK_PKG_SRC_PATH/image ]]; then 
        echo "no docker image directory under $BK_PKG_SRC_PATH. please extract it first."
        return 1
    fi
    if ! [[ -d /opt/yum ]]; then 
        echo "no yum directory under /opt,  please extract it first."
        return 1
    fi
    for ver in 8 11; do
        if ! [[ -r $BK_PKG_SRC_PATH/java${ver}.tgz ]]; then
            echo "no java${ver}.tgz under $BK_PKG_SRC_PATH,  please download a jdk${ver} and rename it to java${ver}.tgz."
            return 1
        fi
        if [[ $(tar tf $BK_PKG_SRC_PATH/java${ver}.tgz | awk '$NF ~ /\/bin\/java$/' | wc -l) -eq 0 ]]; then 
            echo "java${ver}.tgz不是一个合法的jre包，找不到bin/java结尾的文件"
            return 1
        fi
    done
}

is_module_odd_num () {
    local module=$1
    local num=$(eval echo \${#${module}_IP[@]})
    if [[ $num -gt 0 && $((num%2)) -eq 0 ]]; then
       echo "$module 模块(当前值$num)在install.config中数量为偶数，而不是奇数。"
       return 1
    fi
}

is_string_in_array() {
    local e
    for e in "${@:2}"; do
        [[ "$e" == "$1" ]] && return 0
    done
    return 1
}

check_install_config () {
    local ip
    local ret=0
    # gse redis on same host
    for ip in ${BK_GSE_IP[@]}; do
        if is_string_in_array "$ip" ${BK_REDIS_IP[@]}; then
            ret=0
            break
        else
            ret=1
        fi
    done
    if [[ $ret -ne 1 ]]; then
        echo "gse和redis不在同一台机器上"
    fi

    for m in BK_CONSUL BK_KAFKA BK_ZK ; do
       is_module_odd_num $m || ((++ret))
    done
    return "$ret"
}

check_python_version () {
    local rt=0
    if [[ $(/opt/py27/bin/python --version 2>&1) != "Python 2.7.10" ]]; then
        echo "/opt/py27/bin/python的版本不为2.7.10"
        ((rt++))
    fi
    if [[ $(/opt/py27_e/bin/python2.7_e --version 2>&1) != "Python 2.7.91" ]]; then
        echo "/opt/py27_e/bin/python加密解释器的版本不为2.7.91"
        ((rt++))
    fi
    if [[ $(/opt/py36/bin/python --version 2>&1) != "Python 3.6.10" ]]; then
        echo "/opt/py36/bin/python的解释器的版本不为3.6.10"
        ((rt++))
    fi
    if [[ $(/opt/py36_e/bin/python3.6_e --version 2>&1) != "Python 3.6.61" ]]; then
        echo "/opt/py36/bin/python3.6_e的解释器的版本不为3.6.61"
        ((rt++))
    fi
    if [[ $(/opt/py36_e/bin/pip freeze | awk -F= '/^(virtualenv|virtualenvwrapper)==/{print $3}') != $'20.0.34\n4.8.4' ]]; then
        echo "/opt/py36_e/bin/pip freeze输出的virtualenv 和virtualenvwrapper的版本不符合预期"
        ((rt++))
    fi
    return "$rt"
}

do_check() {
    local item=$1
    local step_file=$HOME/.bk_controller_check

    if grep -qw "$item" "$step_file"; then
         echo "<<$item>> has been checked successfully... SKIP"
    else
         echo -n "start <<$item>> ... "
         message=$($item)
         if [ $? -eq 0 ]; then
             echo "[OK]"
             echo "$item" >> $step_file
         else
             echo "[FAILED]"
             echo -e "\t$message"
             exit 1
         fi
    fi
}

if [[ -z $BK_PRECHECK ]]; then
    BK_PRECHECK="check_ssh_nopass check_hostname_uniq check_cert_mac 
    check_install_config check_domain check_src_dir"
fi

STEP_FILE=$HOME/.bk_controller_check

# 根据参数设置标记文件
if [ "$1" = "-r" -o "$1" = "--rerun" ]; then
    > "$STEP_FILE"
else
   [ -e "$STEP_FILE" ] || touch "$STEP_FILE"
fi

for item in $BK_PRECHECK
do
   do_check "$item"
done