# 更新日志

## install 3.0

### 依赖开源组件版本升级

开源组件更新为rpm包方式部署，并升级版本如下：

- consul 1.7.9
- consul-template 0.25.1
- docker 18.09.9
- elasticsearch 7.6.1
- influxdb 1.7.10
- kafka 0.10.2.0
- mysql 5.7.29
- redis 5.0.9
- zookeeper 3.4.14
- rabbitmq 3.8.3
- openresty 1.15.8.3 
- mongodb 4.2.3 

### 安全更新

- 蓝鲸后台模块除gse外，均使用blueking，低权限账号启动，不再使用root账号
- 开源组件使用rpm包安装，且创建相应低权限账号运行，不再使用root账号
- Redis Sentinel模式下，增加密码认证
- zookeeper默认启动参数禁用jmx的远程访问
- influxdb 默认增加密码认证
- nginx的ssl_protocols配置调整只支持TLSv1.2 TLSv1.3协议

### 蓝鲸产品部署调整

- [新增] 蓝鲸后台模块除gse外，均使用blueking账户启动，systemd托管。
- [变更] 蓝鲸配置渲染方式重构，模板占位符统一`BK_`前缀避免潜在和开源软件的变量冲突的可能
- [部署] pip包安装统一为离线本地pip源安装方式
- [优化] 部署前初始化蓝鲸安装主机，并对每个节点做基础检查
- [变更] 安装部署蓝鲸组件的脚本剥离为独立的install_*.sh脚本
- [新增] 新增release_*.sh 脚本用于单独更新蓝鲸组件包
- [新增] 新增health_check/check_*.sh脚本用于检查蓝鲸的服务状态
- [变更] 切换confd生成nginx配置为consul-template来动态生成nginx配置
- [变更] 使用openresty来代替nginx作为web接入层
- [变更] 进程守护使用systemd，不再添加crontab的进程检查脚本
- [优化] 使用pssh套件代替串行执行ssh命令执行远程命令
- [变更] Python工程均使用蓝鲸加密python解释器部署，保护源码
- [变更] Consul健康检查从脚本判断进程调整为TCP检测端口存活
- [变更] 删除原来脚本框架的不再使用的脚本