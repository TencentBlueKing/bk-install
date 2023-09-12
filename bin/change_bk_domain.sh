#!/usr/bin/env bash
# Description: 修改蓝鲸组件的默认域名

SELF_DIR=$(dirname $(readlink -f $0))

NEW_DOMAIN=$1
OLD_DOMAIN=${2:-bktencent.com}
LESSCODE_MODULE=$(grep -o lesscode "$SELF_DIR"/../install.config)
OLD_DOMAIN_NUM=$(grep -cw "bktencent.com" "${SELF_DIR}"/default/global.env)
NEW_DOMAIN_ENV=$(grep -w "$OLD_DOMAIN" "${SELF_DIR}"/default/global.env | sed "s/$OLD_DOMAIN/$NEW_DOMAIN/")
NEW_DOMAIN_ENV_KEYS=( $(awk -F= '{print $1}' <<<"$NEW_DOMAIN_ENV") )

source "${SELF_DIR}"/../utils.fc
emphasize "check the domain name is correct"
# BK_DOMAIN 不能是顶级域名，没有\.字符时
if ! [[ $NEW_DOMAIN =~ \. ]]; then
    echo "BK_DOMAIN不应该是顶级域名，请配置二级域名或者以上"
    exit 1
fi

emphasize "update the new domain name to the specified file"
# delete old analysis records
if [[ -n $LESSCODE_MODULE ]]; then
    "${SELF_DIR}"/../pcmd.sh -m lesscode "sed -i '/${BK_LESSCODE_PUBLIC_ADDR%%:*}/d' /etc/hosts"
    "${SELF_DIR}"/../pcmd.sh -m lesscode "sed -i '/${BK_PAAS_PUBLIC_ADDR%%:*}/d' /etc/hosts"
fi

if [[ ${#NEW_DOMAIN_ENV_KEYS[@]} -lt ${OLD_DOMAIN_NUM} ]]; then
    echo "generate new domain env variables failed"
    exit 1
fi

if [[ -f ${SELF_DIR}/03-userdef/global.env ]]; then
    cp -a "${SELF_DIR}"/03-userdef/{global.env,global.env_$(date +%Y%m%d_%H%M)}
    # delete same keys already exists in global.env
    for k in "${NEW_DOMAIN_ENV_KEYS[@]}"; do
        sed -i "/^${k}=/d" "${SELF_DIR}"/03-userdef/global.env
    done
fi

# append new env keys
echo "$NEW_DOMAIN_ENV" >> "${SELF_DIR}"/03-userdef/global.env

emphasize "regenerate environment variable file"
"${SELF_DIR}"/../bkcli install bkenv 2>/dev/null
"${SELF_DIR}"/../bkcli sync common

emphasize "refresh consul kv"
source "${SELF_DIR}"/../load_env.sh
consul kv put bkcfg/fqdn/paas "${BK_PAAS_PUBLIC_ADDR%%:*}"
consul kv put bkcfg/fqdn/cmdb "${BK_CMDB_PUBLIC_ADDR%%:*}"
consul kv put bkcfg/fqdn/job $(awk -F'[:/]' '{ print $4}' <<<"${BK_JOB_PUBLIC_URL}")
consul kv put bkcfg/fqdn/jobapi $(awk -F'[:/]' '{ print $4}' <<<"${BK_JOB_API_PUBLIC_URL}")
consul kv put bkcfg/fqdn/nodeman $(awk -F'[:/]' '{ print $4}' <<<"${BK_NODEMAN_PUBLIC_DOWNLOAD_URL}")
consul kv put bkcfg/global/lesscode_port "${BK_LESSCODE_PORT}"
consul kv put bkcfg/domain/lesscode "${BK_LESSCODE_PUBLIC_ADDR%%:*}"
consul kv put bkcfg/fqdn/bkapi_check $(awk -F'[:/]' '{ print $4}' <<<"${BK_API_CHECK_PUBLICE_URL}")
#apigw
consul kv put bkcfg/fqdn/bkapi $(awk -F'[:/]' '{ print $4}' <<<"${BK_APIGW_API_PUBLIC_URL}")
consul kv put bkcfg/fqdn/apigw $(awk -F'[:/]' '{ print $4}' <<<"${BK_APIGW_PUBLIC_URL}")

# refresh cmdb job external_url
for code in bk_cmdb bk_job; do
    emphasize "refresh $code external_url"
    bk_code=${code^^}_PUBLIC_URL
    mysql --login-path=mysql-default -e "update open_paas.paas_app set external_url='${!bk_code}' where code='${code}';"
    mysql --login-path=mysql-default -e "SELECT external_url FROM open_paas.paas_app WHERE code = '${code}'\G"
done

# get which module need render
# for k in "${NEW_DOMAIN_ENV_KEYS[@]}"; do grep __${k}__ -rl $BK_PKG_SRC_PATH/*/support-files/templates; done | awk -F/ '{print $4}' | sort -u
NEED_RENDER_MODULES=($(sed 's/\n/\ /g' <<<$(for k in "${NEW_DOMAIN_ENV_KEYS[@]}"; do grep __${k}__ -rl $BK_PKG_SRC_PATH/*/support-files/templates; done | awk -F/ '{print $4}'| sort -u)))

for module in "${NEED_RENDER_MODULES[@]}"; do
    case $module in
        "bk_apigateway")
            module="apigw"
            ;;
        "open_paas")
            module="paas"
            ;;
    esac

    if grep -q "${module}" "$SELF_DIR"/../install.config; then
        if [[ $module != "paas_plugins" ]]; then
            emphasize "Re-render $module config file"
            ./bkcli render "$module" && ./bkcli restart "$module"
        fi
    fi
done

emphasize "Re-render job frontend"
"${SELF_DIR}"/../pcmd.sh -m nginx "${CTRL_DIR}/bin/release_job_frontend.sh -p ${BK_HOME} -B ${BK_PKG_SRC_PATH}/backup -s ${BK_PKG_SRC_PATH}/ -i $BK_JOB_API_PUBLIC_URL"

echo paas cmdb job | xargs -n1 "${SELF_DIR}"/../bkcli check

# re-deploy SaaS
echo "now you can re-deploy all SaaS to apply new BK_DOMAIN"
echo "using command: ./bkcli install saas-o"
