#!/usr/bin/env bash
# 检查蓝鲸平台的状态

default_systemd_patt="^(bk-|cmdb|gse|consul|docker)"
# https://www.freedesktop.org/software/systemd/man/systemd.unit.html
# Valid unit names consist of a "name prefix" and a dot and a suffix specifying the unit type. The "unit prefix" must consist of one or more valid characters (ASCII letters, digits, ":", "-", "_", ".", and "\"). The total length of the unit name including the suffix must not exceed 256 characters. The type suffix must be one of ".service", ".socket", ".device", ".mount", ".automount", ".swap", ".target", ".path", ".timer", ".slice", or ".scope".
systemd_unit_patt='^[a-zA-Z0-9:_.\\-]+(@[a-zA-Z0-9:_.\\-]+)?[.](service|socket|device|mount|automount|swap|target|path|timer|slice|scope)$'

debug (){
  test -n "$DEBUG" && echo >&2 "$@"
}

# systemd状态
# 可以考虑show或者status的输出.
# 颜色定义:
#  绿色 active
#  红色 failed
#  黄色 inactive

# supervisor状态
# 需要检测判断-c参数的supervisor, 并加载对应的conf文件使用.
# 颜色定义:
#  绿色 RUNNING
#  红色 EXITED FATAL BACKOFF
#  黄色 STOPPED
# 官方文档:
# * http://supervisord.org/subprocess.html
# status all输出格式:
# 名称(组名:进程名) 空格*3+ 状态 空格1+ 描述
# 如果为RUNNING, 则描述为 pid 及持续实际
# 如果为STOPPED/EXITTED, 则为停止的时刻.
# 如果为FATAL/BACKOFF, 则为出错提示.
# 其他状态无描述.

# 基础颜色定义.
COLOR_RED_FG=$'\033[31m'
COLOR_GREEN_FG=$'\033[32m'
COLOR_YELLOW_FG=$'\033[33m'
COLOR_BOLD=$'\033[1m'
COLOR_RESET=$'\033[0m'
# 配置高亮的颜色及关键词, 最终关键词前后均有空格, 确保只匹配到整个字段.
colorful_err_patt="EXITED|FATAL|BACKOFF|failed|not-found|deactivating"  # 关键字, |分隔的词.
colorful_err_color="$COLOR_RED_FG$COLOR_BOLD"  # 颜色
colorful_warn_patt="STOPPED|inactive|reloading|activating"  # 关键字, |分隔的词.
colorful_warn_color="$COLOR_YELLOW_FG$COLOR_BOLD"  # 颜色
colorful_ok_patt="RUNNING|active"  # 关键字, |分隔的词.
colorful_ok_color="$COLOR_GREEN_FG$COLOR_BOLD"  # 颜色
# 简单高亮下
colorful (){
  # 排版后, \t 已经全部转换为了空格, 所以这里选择使用空格定界, 防止误匹配.
  sed -r \
    -e "s/ ($colorful_ok_patt) / ${colorful_ok_color}\1${COLOR_RESET} /" \
    -e "s/ ($colorful_err_patt) / ${colorful_err_color}\1${COLOR_RESET} /" \
    -e "s/ ($colorful_warn_patt) / ${colorful_warn_color}\1${COLOR_RESET} /"
}

# 基于systemd show, 未完成.
systemd_show (){
  local id=$1
  [ -z "$id" ] && {
    echo >&2 "Usage: $FUNCNAME service-id"
    return 1
  }
  systemctl show "$id" | awk -F"=" '{
  # 因为没办法实现分为2个字段, 所以跳过1+$1的宽度+FS 1
  kv[$1]=substr($0, 1+length($1)+1)
}
END{
  OFS="\t"
  print kv["Id"], kv["MainPID"], kv["ActiveEnterTimestamp"], kv["ActiveState"], kv["UnitFileState"]
}'

}

convert_systemctl_status (){
  awk -v SYSTEMD_ONLY="${SYSTEMD_ONLY:-}" 'BEGIN{
  OFS="\t"
  stderr="/dev/stderr"
  convert_supervisorctl_status=" status all | sed -E -e \"s/ +/\t/\" -e \"s/ +/\t/\""
  state_ok="active"
}
function status(){
  if(state==state_ok){
    desc="pid " pid " " exec ", uptime " uptime;
  } else {
    desc=state_sub " " uptime " " exec;
  };
  if(svc)print svc,state,desc
  # 如果是supervisord, 且未禁止展开, 则展示子进程信息. 不影响退出码.
  if(exec=="(supervisord)"&&!SYSTEMD_ONLY){  # exec未作处理, 需要包含周围的括号.
    #print "supervisorctl status all:\t\t* "svc" is supervisord, show details."
    print "\t\t* "svc" extra info: supervisorctl status all"
    supervisorctl=gensub(/supervisord/, "supervisorctl", 1, exec_long)
    if(supervisorctl){
      system(supervisorctl convert_supervisorctl_status)
    }else {
      print "\tWARNING\tfailed to detect supervisorctl, skip show supervisord."
    }
  }
  # 清空变量
  svc=""; state=""; state_sub=""; uptime=""; ram=""; pid="";
  exec=""; enabled=""; patt_exec_long="";
}
# 提取所需的字段:
$0~/^[^ ]+ +[^ ]+[.](service|socket|target)/{svc=$2}
$1=="Active:"{
  state=$2;
  if($0~/\(/){ state_sub=$0; sub(/^[^(]+/, "", state_sub); sub(/[^)]+$/, "", state_sub); }
  if($0~/;/){ uptime=$0; sub(/.*; */,"",uptime);}
}
$1=="Loaded:"{ enabled=""; }
$1$2=="MainPID:"{
  pid=$3;
  if($0~/\(/){ exec=$0; sub(/^[^(]+/, "", exec); }
  patt_exec_long="^ *[|`]- *"pid" +"  # status存在 |-PID 或 `-PID 2种情况. PID前可能有空格.
}
$1=="Memory:"{ram=$2;}
patt_exec_long&&$0~patt_exec_long{ exec_long=$0; sub(patt_exec_long, "", exec_long); }

/^ *$/{status(); }; # 针对多行.
END{status();}'
}

pretty(){
  local msg
  if [ -n "$FORCE_TTY" ] || [ -t 1 ]; then
    [ -n "$FORCE_TTY" ] && msg="Force" || msg="we are writing a TTY,"
    debug >&2 "$msg pretty print."
    { echo -e "Service\tStatus\tDescription";
      "$@" 2>&1; } | # 需要合并stdout和stderr.
      sed -r 's/^([a-zA-Z0-9_]+):\1/\1:~/' | # 简化supvisor的自动命名.
      column -t -s $'\t' |  # 排版
      colorful  # 高亮导致column排版异常, 放在结尾.
  else
    "$@" 2>/dev/null | sed -r 's/\x1b[[][0-9;? ]*[@A-HJ-MPXa-hl-nq-su]//g'  # 尝试去除一些常见的CSI序列.
  fi
  #return ${PIPESTATUS[0]}  # 无论何种情况, 都返回自定义命令的返回码.
  # 目前返回状态不可靠, 需要研究确认systemctl及supervisorctl的返回码后方可.
  # 且需层层传递返回码, 故而放弃传递返回码.
  return 0
}

list_systemd_services (){
  systemctl list-units -t service -a --no-legend --state=loaded | awk '{sub(/^[* ]+/, ""); print $1;}'
}

status_systemd (){
  debug "func: $FUNCNAME: $*"
  local svc
  for svc in $(expand_systemd_services "$@"); do
    systemctl -n 0 status "$svc" | convert_systemctl_status
  done
}

expand_systemd_services (){
  list_systemd_services | awk -v systemd_unit_patt="$systemd_unit_patt" '
BEGIN{
  stderr="/dev/stderr"
  stdin="/dev/stdin"
  while(getline < stdin){
    systemd_services[$0]=0
  }
}
BEGINFILE{
  patt=FILENAME
  if(patt~systemd_unit_patt){
    msg=patt"\tnot-found\t* service not loaded, or name is wrong.\n"
    gsub(/[.]/,"[&]", patt)
    patt="^"patt"$"
  }else{
    msg="\t\t* PATT %s matches nothing.\n"
  }
  n=0;
  for(svc in systemd_services){
    if(svc~patt){
      n++
      if(!systemd_services[svc]++)print svc
    }
  }
  if(n==0){printf msg, patt > stderr; }
  nextfile
}
' "$@"
}

main (){
  export LC_ALL=C  # 所有文本通配基于locale=C测试. systemd会识别语言及utf-8调整输出样式.
  if ! command -v systemctl >/dev/null; then echo >&2 "command systemctl not found, skip."; return 1; fi
  local ret=0
  if test $# -eq 0; then
    debug "using default patt: $*"
    set -- "$default_systemd_patt"
  else
    debug "PATT are: $*"
  fi
  status_systemd "$@"
  return $ret
}

usage (){
  cat <<EOF
Usage: $0 [UNIT_NAME|PATT...]  -- show status of BlueKing systemd services.

UNIT_NAME should match $systemd_unit_patt
otherwise it will be treat as a PATT, which should be a valid value of "grep -E".
the output UNIT_NAME is unique.

if no UNIT_NAME or PATT given, using default PATT: "$default_systemd_patt"

exit code:
always return 0. It's not suitable for status detecting.

ENV:
* "DEBUG", set to 1 to enable debug message.
* "FORCE_TTY": set to 1 to force pretty print, even stdout is not a tty.
* "SYSTEMD_ONLY": set to 1 to disable expand process status. such as supervisord.
EOF
  if test -n "$DEBUG"; then
    cat <<EOF

detector is:
$(declare -f list_systemd_services)
EOF
  fi
}

# 处理参数. 目前并无参数, 那么仅 --help.
if test $# -gt 0 && test "x$*" != "x${*/#--help/}"; then
  usage
else
  pretty main "$@"
fi

