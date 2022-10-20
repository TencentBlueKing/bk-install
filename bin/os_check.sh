#!/usr/bin/env bash

is_systemd () {
    local init_cmd
    read -r init_cmd < /proc/1/cmdline
    [[ $init_cmd =~ systemd ]]
}

# 修改 /etc/systemd/system.conf 后需要运行以下命令来
# systemctl daemon-reexec