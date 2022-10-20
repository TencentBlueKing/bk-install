#!/usr/bin/env bash
# 用途：根据传入的env文件顺序，依次加载，然后对比差异

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <file1,file2,file3> <File1,File2,File3>"
    echo "       脚本先依次加载file1,file2,file3，然后导出环境变量"
    echo "       然后依次加载File1,File2,File3，然后再导出环境变量"
    echo "       最后进行对比"
    exit 1
fi

first=()
second=()

IFS=, read -r -a first <<<"$1"
IFS=, read -r -a second <<<"$2"

env_first=$(mktemp /tmp/env.diff.XXXX)
env_second=$(mktemp /tmp/env.diff.XXXX)

trap 'rm -f $env_first $env_second' EXIT

command=$(printf "source %s;" "${first[@]}")
env -i bash -c "set -a ;$command env" | sort > "$env_first"

command=$(printf "source %s;" "${second[@]}")
env -i bash -c "set -a ;$command env" | sort > "$env_second"

diff "$env_first" "$env_second"