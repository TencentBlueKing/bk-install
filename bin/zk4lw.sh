#!/usr/bin/env bash
# From documentation: https://zookeeper.apache.org/doc/r3.4.10/zookeeperAdmin.html#sc_zkCommands
# conf: New in 3.3.0: Print details about serving configuration.
# 
# cons: New in 3.3.0: List full connection/session details for all clients connected to this server. Includes information on numbers of packets received/sent, session id, operation latencies, last operation performed, etc...
# 
# crst: New in 3.3.0: Reset connection/session statistics for all connections.
# 
# dump: Lists the outstanding sessions and ephemeral nodes. This only works on the leader.
# 
# envi: Print details about serving environment
# 
# ruok: Tests if server is running in a non-error state. The server will respond with imok if it is running. Otherwise it will not respond at all.  A response of "imok" does not necessarily indicate that the server has joined the quorum, just that the server process is active and bound to the specified client port. Use "stat" for details on state wrt quorum and client connection information.
# 
# srst: Reset server statistics.
# 
# srvr: New in 3.3.0: Lists full details for the server.
# 
# stat: Lists brief details for the server and connected clients.
# 
# wchs: New in 3.3.0: Lists brief information on watches for the server.
# 
# wchc: New in 3.3.0: Lists detailed information on watches for the server, by session. This outputs a list of sessions(connections) with associated watches (paths). Note, depending on the number of watches this operation may be expensive (ie impact server performance), use it carefully.
# 
# wchp: New in 3.3.0: Lists detailed information on watches for the server, by path. This outputs a list of paths (znodes) with associated sessions. Note, depending on the number of watches this operation may be expensive (ie impact server performance), use it carefully.
# 
# mntr: New in 3.4.0: Outputs a list of variables that could be used for monitoring the health of the cluster.

if [[ $# -eq 1 ]]; then
    ZK_4LW="$1"
elif [[ $# -eq 2 ]]; then
    ZK_ADDR="$1"
    ZK_4LW="$2"
else
    echo "Usage: $0 <zk_host:zk_port> <zk_four_letter_word>"
    exit 1
fi

ZK_HOST=${ZK_ADDR%%:*}
ZK_PORT=${ZK_ADDR##*:}
ZK_ALL_4LW=( conf cons crst dump envi ruok srst srvr stat wchs wchc wchp mntr )

if ! [[ $ZK_HOST =~ ^[a-z0-9.-]+$ ]]; then
    echo "$ZK_HOST is not a valid host/ip."
    exit 1
fi
if ! [[ $ZK_PORT =~ ^[0-9]+$ ]]; then
    echo "$ZK_PORT is not a valid port number."
    exit 1
fi
if ! printf "%s\n" "${ZK_ALL_4LW[@]}" | grep -qw "$ZK_4LW"; then
    echo "zookeeper 4 letter word: ${ZK_ALL_4LW[*]}"
    exit 1
fi

exec 3<> /dev/tcp/$ZK_HOST/$ZK_PORT
echo "$ZK_4LW" >&3;
cat 0<&3

# close fd
exec 3>&-
