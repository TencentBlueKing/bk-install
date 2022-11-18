#!/usr/bin/env bash
# shellcheck disable=1090
# 用途：一次性迁移原来的环境变量到新的环境变量

SELF_DIR=$(readlink -f "$(dirname $0)")

source "$SELF_DIR"/../utils.fc

case "$1" in
    job)
        # for JOB
        BK_JOB_APP_SECRET=$(_app_token bk_job)
        echo "BK_JOB_APP_SECRET=$BK_JOB_APP_SECRET"
        for m in BK_JOB_EXECUTE BK_JOB_MANAGE BK_JOB_CRONTAB BK_JOB_BACKUP; do
            printf "%s_MYSQL_HOST=%q\n" "$m" "$MYSQL_IP0"
            printf "%s_MYSQL_PORT=%q\n" "$m" "$MYSQL_PORT"
            printf "%s_MYSQL_USERNAME=%q\n" "$m" "$MYSQL_USER"
            printf "%s_MYSQL_PASSWORD=%q\n" "$m" "$MYSQL_PASS"
            printf "%s_REDIS_PORT=%q\n" "$m" "$REDIS_PORT"
            printf "%s_REDIS_PASSWORD=%q\n" "$m" "$REDIS_PASS"
            printf "%s_REDIS_SENTINEL_NODES=%q\n" "$m" "$REDIS_CLUSTER_HOST:$REDIS_CLUSTER_PORT"
            printf "%s_REDIS_SENTINEL_MASTER=%q\n" "$m" "$REDIS_MASTER_NAME"
        done
        ;;
    *)
        echo "Usage: $0 <模块>"
        exit 1
        ;;
esac