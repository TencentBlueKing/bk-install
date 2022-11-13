#!/usr/bin/gawk -f
# parse blueking install.config and generate env file.
# generate 02-dynamic/MODULE-host.env , formerly named config.env.
# Usage: ./bk-install-config-parser.awk /path/to/install.config > /path/to/env-file
# ENV:
# DEBUG: 值非空, 则显示debug信息.

# 1. 行的格式:
# 1.1. 分组定义, 以方括号[]包含的任意字符串? 不过对env生成无影响, 忽略.
# 1.2. 模块分布定义, 第一个字段为IP, 第二个字段为逗号分隔的模块工程定义.
# 1.2.1. IP目前应该仅IPv4, 应该考虑IPv6.
# 1.2.2. 模块工程定义分为3种.
# 1.2.2.1. 蓝鲸模块或第三方服务: 名称(亦是src/或src/services/下的目录名, 暂不检查).
# 1.2.2.2. 蓝鲸模块里的工程: 蓝鲸模块名"("模块内的工程名")"
# 1.2.2.3. 第三方服务为特定蓝鲸模块提供的实例: 第三方服务名"("蓝鲸模块名")"
# 1.3. 注释行: 以#开头的行.
# 1.4. 空白行: 含有任意长度空白字符的行, 用于结束组. EOF也会结束组.
# 1.5. 标签行: 以:开头, 但是早期pxs未支持解析, 直接忽略. 故此保留识别不做处理.

# 2. 输出的变量名称
# 2.1. 全局
# 2.1.1. ALL_IP 全部IP地址
# 2.1.2. ALL_MODULE  全部模块名称 早期模块结尾可以带数字, 需要过滤掉.
# 2.1.3. ALL_NAME  全部项目名称 如无则为模块名 如 cmdb ci@process bcs@monitor
# 2.2. 蓝鲸模块
# 2.2.1. 变量前缀:
# 2.2.1.1. 此前直接使用模块名作为前缀, 今后使用 BK_模块 前缀.
# 2.2.1.2. 如果含有多个工程, 则额外提供 BK_模块_工程 前缀的变量.
# 2.2.2. 变量后缀:
# 2.2.2.1. IP 数组, 保存所有IP.
# 2.2.2.2. HOST 字符串, 默认主机名. (会添加多条解析吗?)
# 2.2.2.3. IPn 字符串, n此前为数组下标, 今为自然数, 和NODEn_HOST一致. 为了兼容提供IP0, 值为IP1.
# 2.2.2.4. NODEn_HOST 字符串, n为自然数. 早期值为IP第一个NAME的host, 此处改为根据当前NAME命名.
# 2.2.2.5. IP_COMMA 字符串, 新增变量. 逗号分隔的IP列表.

BEGIN{
  FS="[ \t,]+"
  # 一些正则.
  patt_ipv4="([0-9]+[.]){3}[0-9]+"
  # TODO, IPv6 0-9a-f, 允许单次出现连续的::. 目前暂定: ([0-9a-f]+:)*:?(:[0-9a-f]+)+
  # 需要补充一些测试用例.
  #patt_ipv6=""
  patt_non_hostname_char="[^a-z0-9.-]"
  # 可能的格式见1.2.2定义
  patt_word="[a-zA-Z][a-zA-Z0-9_]*"
  patt_non_word_char="[^a-zA-Z0-9_]"
  patt_word_lower="[a-z][a-z0-9_]*"
  patt_module_proj="("patt_word_lower")(\\(("patt_word_lower "(-" patt_word_lower")*)\\))?"
  patt_name_sanitized="^[A-Z][A-Z0-9_]*$"
  # 域名配置
  domain_service=".service.consul"
  domain_node=".node.consul"
  # utils:
  stderr="/dev/stderr"
  DEBUG=ENVIRON["DEBUG"]
  arprint_fmt="%s=%s\n"  # key=value.
  arprint_sep="_"  # key separator. here is "_".
  # 如果存在dynamic目录. 则自动生成一些中间文件备用.
  "bash -c 'cd $CTRL_DIR/bin/02-dynamic 2>/dev/null && echo $PWD'" | getline dynamic_dir
  if(dynamic_dir){
    if(DEBUG){print "dynamic_dir detected:", dynamic_dir > stderr }
    install_config_parsed=dynamic_dir"/install-config.parsed"
  }
}

# ip转为整数. 方便排序.
function ip2int(ip,    aip){
  split(ip, aip, /[.]/)
  return aip[1]*256**3+aip[2]*256**2+aip[3]*256+aip[4]
}

# join数组. awk不支持数组, 这里的数组都是模拟的. 或者直接join map keys?
function join(array, sep,     elements, error){
  error=0
  if(!isarray(array)){ print "ERROR: ARGV1 is not an array, value is", array > stderr; error+=1; }
  if(!sep){ print "ERROR: sep not set."; error+=1; }
  if(error>0){ print "Usage: join(array, sep)  -- concat ARRAY to str, separated by SEP."; return 1; }
  elements=""
  for(i=0; i<length(array); i++){
    if(i in array){
      elements = elements sep array[i]
    } else { print "ERROR: array key was not found:", i, ". length is", length(array) > stderr; return 2; }
  }
  # 移除开头的sep. substr从1计数.
  return substr(elements, 1+length(sep))
}
# join array的key.
function joink(array, sep, sorter,     elements, k){
  if(!sorter)sorter="@ind_str_asc"
  if(!sep)sep=" "
  PROCINFO["sorted_in"]=sorter
  for(k in array){
    elements=elements sep k
  }
  return substr(elements, 1+length(sep))
}

# 标准化主机名称, 这里偷懒, 不检查长度. FQDN最长253B, 单节NAME 63B.
function hostname_sanitize(hostname){
  return gensub(patt_non_hostname_char, "-", "g", tolower(hostname))
}
# 标准化变量名称, 把非word转为下划线.
function bk_var_name_sanitize(module){
  return toupper(gensub(patt_non_word_char, "_", "g", module))
}
# 变量引用, 如果存在单引号, 则使用双引号.
function bk_var_value_quoted(value){
  # 目前简单去除单引号, 然后在前后加上单引号.
  return "\x27" gensub(/\x27/, "", "g", value) "\x27"
}

# 统一注册管理.
# 新版: 注册数组, 值为IP str:
# ip2proj[ip2int][mod][proj]
# proj2ip[mod][proj][number], 值为IPstr. 那么怎么去重? 查ip2proj[ip2int][mod][proj]?
# 遍历上述数组, 得出ip到模块, 或者无proj, 则表示为 proj=""?
# 同步记录发现的mod或proj.
# all_ip
# all_mod
# all_proj, 即all_name? 还是展开all_name?
function bk_module_proj_reg(module, proj, ip,    ipint, idx_p, idx_m){
  # proj默认为空字符串.
  if(!proj)proj="";
  # 此前的 name为 module 或 module@proj 形式.
  proj=="" ? bk_name=module : bk_name=module "@" proj
  # 记录all_ip, 同时保持其出现次序.
  if(!all_ip[ip]){all_ip[ip]=++ip_count}
  all_module[module]=1
  all_name[bk_name]=1
  # 将IP转为整数, 方便排序.
  ipint=ip2int(ip)
  # 如果ip2proj对应key为空, 则说明是新增.
  if(length(ip2proj[ipint][module][proj])==0){
    if(install_config_parsed){
      print ip, module, proj > install_config_parsed
    }
  }  # 不必提示重复定义. 静默忽略即可.
  # 注册proj, 值为IP次序, 故可重复执行.
  proj2ip[module][proj][ip]=all_ip[ip]
  # 同理更新module.
  proj2ip[module][""][ip]=all_ip[ip]
  # 注册
  ip2proj[ipint][module][proj]=ip
}

# 目前仅关注ipv4开头的行. 其他的全部忽略.
{
  if($1~"^"patt_ipv4"$"){
    ip=$1
    # 处理 模块+工程
    for(i=2; i<=NF; i++){
      proj=$i
      #  print name4proj(proj), ip
      if(proj~"^"patt_module_proj"$"){
        match(proj, patt_module_proj, a_proj)
        # 统一标准化处理. 参数: 模块, 工程, ip
        bk_module_proj_reg(a_proj[1], a_proj[3], ip)
      } else {
        print "ERROR: invalid format:", FILENAME":"FNR":Field" i":" , proj > stderr;
        exit_code=1;
      }
    }
  } else if(DEBUG){ print "ignore line:",$0 > stderr; }
}

END{
  # 处理ALL_IP, ALL_MODULE, ALL_NAME等变量.
  print "ALL_IP=(" joink(all_ip, " ", "@val_num_asc") ")"  # 保持原次序输出
  print "ALL_IP_COMMA='" joink(all_ip, ",", "@val_num_asc") "'"  # 保持原次序输出
  print "ALL_MODULE=(" joink(all_module) ")"  # 为按字符排序后的版本.
  print "ALL_NAME=(" joink(all_name) ")"  # 为按字符排序后的版本.
  # 处理具体的模块及工程.
  # 输出 BK_MODULE_IP=() BK_MODULE_IP0 BK_MODULE_IP_COMMA
  # 输出 BK_MODULE_PROJ_PROJ_IP=() BK_MODULE_PROJ_IP0 BK_MODULE_PROJ_IP_COMMA
  PROCINFO["sorted_in"]="@ind_str_asc"
  for(m in proj2ip){
    PROCINFO["sorted_in"]="@ind_str_asc"
    for(p in proj2ip[m]){
      if(p==""){
        pfx="BK_"m
      } else {
        pfx="BK_"m"_"p
      }
      pfx=bk_var_name_sanitize(pfx)
      # 输出数组.
      print pfx"_IP=(" joink(proj2ip[m][p], " ", "@val_num_asc") ")"
      print pfx"_IP_COMMA='" joink(proj2ip[m][p], ",", "@val_num_asc") "'"
      # 输出带序号的变量名.
      n=0
      PROCINFO["sorted_in"]="@val_num_asc"
      for(ip in proj2ip[m][p]){
        print pfx"_IP" n "='" ip "'"
        n++
      }
    }
  }
  # IP2NAME?
  # 输出 BK_IP2NAME_0_0_0_0=(name...)
  exit(exit_code)
}
