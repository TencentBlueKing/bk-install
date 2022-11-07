#!/usr/bin/env bash
# 用途:    1. 对于还没有使用ssh-copy-id等手段配置key的机器，可以使用本脚本来拷贝
#          2. 手动安装agent时，可以用它来实现基础的批量安装

SSH_PORT=22
SSH_USER=root
CONFIG_FILE=$1
COMMAND="$2"

TMP_SSH_CONFIG=$(mktemp /tmp/ssh_config_XXXXXX)
TMP_SSH_CONFIG_PASSWORD_DIR=$(mktemp -d /tmp/ssh_config_password_XXXXXX)
trap 'rm -rf $TMP_SSH_CONFIG $TMP_SSH_CONFIG_PASSWORD_DIR' EXIT

### check sshpass command
if ! command -v sshpass &>/dev/null; then
    if ! yum -y install sshpass; then
        echo "install <sshpass> package with yum failed"
        exit 1
    fi
fi

### setup ssh_config
cat >"$TMP_SSH_CONFIG" <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    GlobalKnownHostsFile /dev/null
    LogLevel ERROR
EOF

i=1
declare -a hosts=()
while read -r ip password user port; do 
    hosts+=("host-$i")
    cat <<EOF >> "$TMP_SSH_CONFIG"

Host host-$i
    HostName $ip
    User ${user:-$SSH_USER}
    Port ${port-$SSH_PORT}
EOF
    echo "$password" > "$TMP_SSH_CONFIG_PASSWORD_DIR/host-$i"
    ((i++))
done < "$CONFIG_FILE"

# do the logic
case $COMMAND in 
    pubkey) 
        for h in "${hosts[@]}"; do
            rsync -a $HOME/.ssh/id_rsa* $HOME/.ssh/authorized_keys -e "sshpass -f $TMP_SSH_CONFIG_PASSWORD_DIR/$h ssh -F $TMP_SSH_CONFIG" $h:$HOME/.ssh/
        done
        ;;
    *)
        for h in "${hosts[@]}"; do
            sshpass -f "$TMP_SSH_CONFIG_PASSWORD_DIR/$ip" ssh -F "$TMP_SSH_CONFIG" "$h" "$COMMAND"
        done
        ;;
esac
