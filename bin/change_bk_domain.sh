#!/usr/bin/env bash
# Description: 修改蓝鲸组件的默认域名

SELF_DIR=$(dirname $(readlink -f $0))

NEW_DOMAIN=$1
OLD_DOMAIN=${2:-bktencent.com}

# BK_DOMAIN 不能是顶级域名，没有\.字符时
if ! [[ $NEW_DOMAIN =~ \. ]]; then
    echo "BK_DOMAIN不应该是顶级域名，请配置二级域名或者以上"
    exit 1
fi

# delete old analysis records
source ${SELF_DIR}/../utils.fc
"${SELF_DIR}"/../pcmd.sh -m lesscode "sed -i '/${BK_LESSCODE_PUBLIC_ADDR%%:*}/d' /etc/hosts"
"${SELF_DIR}"/../pcmd.sh -m lesscode "sed -i '/${BK_PAAS_PUBLIC_ADDR%%:*}/d' /etc/hosts"

NEW_DOMAIN_ENV=$(grep -w "$OLD_DOMAIN" ${SELF_DIR}/default/global.env | sed "s/$OLD_DOMAIN/$NEW_DOMAIN/")
NEW_DOMAIN_ENV_KEYS=( $(awk -F= '{print $1}' <<<"$NEW_DOMAIN_ENV") )

if [[ ${#NEW_DOMAIN_ENV_KEYS[@]} -lt 12 ]]; then
    echo "generate new domain env variables failed"
    exit 1
fi 

if [[ -f ${SELF_DIR}/03-userdef/global.env ]]; then
    cp -a ${SELF_DIR}/03-userdef/{global.env,global.env_$(date +%Y%m%d_%H%M)}
    # delete same keys already exists in global.env
    for k in "${NEW_DOMAIN_ENV_KEYS[@]}"; do 
        sed -i "/^${k}=/d" ${SELF_DIR}/03-userdef/global.env 
    done
fi

# append new env keys
echo "$NEW_DOMAIN_ENV" >> "${SELF_DIR}"/03-userdef/global.env

${SELF_DIR}/../bkcli install bkenv 2>/dev/null
${SELF_DIR}/../bkcli sync common

# refresh consul kv 
source ${SELF_DIR}/../load_env.sh 
consul kv put bkcfg/fqdn/paas "${BK_PAAS_PUBLIC_ADDR%%:*}"
consul kv put bkcfg/fqdn/cmdb "${BK_CMDB_PUBLIC_ADDR%%:*}"
consul kv put bkcfg/fqdn/job $(awk -F'[:/]' '{ print $4}' <<<"${BK_JOB_PUBLIC_URL}")
consul kv put bkcfg/fqdn/jobapi $(awk -F'[:/]' '{ print $4}' <<<"${BK_JOB_API_PUBLIC_URL}")
consul kv put bkcfg/fqdn/nodeman $(awk -F'[:/]' '{ print $4}' <<<"${BK_NODEMAN_PUBLIC_DOWNLOAD_URL}")
consul kv put bkcfg/global/lesscode_port "${BK_LESSCODE_PORT}"
consul kv put bkcfg/domain/lesscode "${BK_LESSCODE_PUBLIC_ADDR%%:*}"

# get which module need render 
# for k in "${NEW_DOMAIN_ENV_KEYS[@]}"; do grep __${k}__ -rl $BK_PKG_SRC_PATH/*/support-files/templates; done | awk -F/ '{print $4}' | sort -u
echo bklog bkmonitorv3 bknodeman cmdb fta job paas usermgr | xargs -n1 ./bkcli render
# job frontend
${SELF_DIR}/../pcmd.sh -m nginx "${CTRL_DIR}/bin/release_job_frontend.sh -p ${BK_HOME} -B ${BK_PKG_SRC_PATH}/backup -s ${BK_PKG_SRC_PATH}/ -i $BK_JOB_API_PUBLIC_URL"
echo paas usermgr cmdb job | xargs -n1 ${SELF_DIR}/../bkcli restart
sleep 15 
echo paas cmdb job | xargs -n1 ${SELF_DIR}/../bkcli check 
echo bklog bkmonitorv3 bknodeman fta | xargs -n1 ${SELF_DIR}/../bkcli restart 

# re-deploy SaaS
echo "now you can re-deploy all SaaS to apply new BK_DOMAIN"
echo "using command: ./bkcli install saas-o"
