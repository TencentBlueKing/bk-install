#!/usr/bin/env bash
# shellcheck disable=SC1091
# 检查license和证书文件是否匹配

TRUE="\e[1;32mtrue\e[0m"
FALSE="\e[1;31mfalse\e[0m"

CERT_API_URL=$(curl -s http://127.0.0.1:8500/v1/catalog/service/license | jq -r '.[] | [.ServiceAddress,.ServicePort] | @tsv' | awk '{print "https://" $1 ":" $2 "/certificate" }' | head -1)
if [[ -z "$CERT_API_URL" ]]; then
    printf "%-15s: %-7b" "license" "${FALSE}"
    echo " Reason: license service is registerd in consul."
    exit 
fi

. "$HOME/.bashrc"
if ! [[ -r $BK_HOME/cert/platform.cert ]]; then
    printf "%-15s: %-7b" "license" "${FALSE}"
    echo " Reason: $BK_HOME/cert/platform.cert doesn't exist."
    exit 
fi

CERT_STRING=$(awk 'BEGIN { ORS="\\n" } 1' $BK_HOME/cert/platform.cert)
PLATFORM="open_paas"
TIMESTAMP=$(date -u +"%F %T")

printf -v JSON_MSG '{ "certificate": "%s", "platform": "%s", "requesttime": "%s" }\n' \
    "$CERT_STRING" "$PLATFORM" "$TIMESTAMP"
    
RESP=$(curl -s -k -d "$JSON_MSG" -H "Content-Type: application/json" -X POST "$CERT_API_URL")
if [[ $RESP =~ success ]]; then
    printf "%-15s: %-7b\n" "license" "${TRUE}"
else
    printf "%-15s: %-7b" "license" "${FALSE}"
    if [[ -z "$RESP" ]]; then
        echo " Reason: license_server api url($CERT_API_URL) refused."
    else
        echo " Reason: $RESP"
    fi
fi
