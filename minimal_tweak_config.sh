#!/usr/bin/env bash

export LC_ALL=C LANG=C
SELF_DIR=$(dirname $(readlink -f $0))

BK_PKG_SRC_PATH=${SELF_DIR%/*}/src

# adjust open_paas uwsgi process number using cheaper system
for f in $BK_PKG_SRC_PATH/open_paas/support-files/templates/#etc#uwsgi-open_paas*.ini; do
    sed -i '/^cheaper/d' "$f"
    cat <<EOF >> $f 
cheaper = 4
cheaper-initial = 4
cheaper-algo = busyness
cheaper-overload = 5
cheaper-step = 2
cheaper-busyness-multiplier = 60
EOF
done

sed -i '/gunicorn/s/-w [0-9][0-9]/-w 2/' $BK_PKG_SRC_PATH/fta/support-files/templates/#etc#supervisor-fta-fta.conf 
sed -i '/gunicorn wsgi/s/-w [0-9][0-9]/-w 2/' $BK_PKG_SRC_PATH/usermgr/support-files/templates/#etc#supervisor-usermgr-api.conf
