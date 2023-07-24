#!/opt/py36/bin/python
# -*- coding: utf8
# 部署可用性检查脚本
import time
import socket
import traceback
import sys 
import os 
from pymongo.common import clean_node
import requests
import re
import logging
import argparse
import pika
import colorlog
import pymysql
import json
import pymongo
import redis
from paramiko import SSHClient, AutoAddPolicy
from redis.sentinel import Sentinel
from kazoo.client import KazooClient
from kazoo.exceptions import NoAuthError
from elasticsearch import Elasticsearch


environ_list = { 
                'dbadmin': ["BK_CONSUL_KEYSTR_32BYTES", "BK_MONGODB_KEYSTR_32BYTES", "BK_MONGODB_ADMIN_USER", "BK_MONGODB_ADMIN_PASSWORD", "BK_MYSQL_ADMIN_USER", "BK_MYSQL_ADMIN_PASSWORD", "BK_RABBITMQ_ADMIN_USER", "BK_RABBITMQ_ADMIN_PASSWORD", "BK_REDIS_SENTINEL_PASSWORD",],
                'paas':  ["BK_PAAS_ES7_ADDR",'BK_PAAS_PUBLIC_ADDR', 'BK_PAAS_MYSQL_HOST', 'BK_PAAS_MYSQL_PASSWORD', 'BK_PAAS_MYSQL_PORT', 'BK_PAAS_MYSQL_USER', 'BK_PAAS_MYSQL_NAME', "BK_IAM_PRIVATE_ADDR", "BK_PAAS_ESB_SECRET_KEY", "BK_PAAS_APP_CODE","BK_PAAS_APP_SECRET", "BK_PAAS_REDIS_HOST","BK_PAAS_REDIS_PASSWORD","BK_PAAS_REDIS_PORT", 'BK_USERMGR_PRIVATE_ADDR'],
                'usermgr': ["BK_DOMAIN", "BK_HOME", "BK_CERT_PATH", "BK_HTTP_SCHEMA", "BK_LICENSE_PRIVATE_ADDR", "BK_PAAS_PUBLIC_ADDR", "BK_PAAS_PUBLIC_URL", "BK_IAM_PRIVATE_URL", "BK_PAAS_ESB_SECRET_KEY", "BK_PAAS_APP_SECRET", "BK_USERMGR_PRIVATE_ADDR", "BK_PAAS_ADMIN_PASSWORD", "BK_PAAS_ADMIN_USERNAME", "BK_USERMGR_APP_CODE", "BK_USERMGR_APP_SECRET", "BK_USERMGR_MYSQL_HOST", "BK_USERMGR_MYSQL_PASSWORD", "BK_USERMGR_MYSQL_PORT", "BK_USERMGR_MYSQL_USER", "BK_USERMGR_RABBITMQ_HOST", "BK_USERMGR_RABBITMQ_PORT", "BK_USERMGR_RABBITMQ_USERNAME", "BK_USERMGR_RABBITMQ_PASSWORD", "BK_USERMGR_RABBITMQ_VHOST",],
                'bkiam': ["BK_HOME", "BK_IAM_PORT", "BK_PAAS_MYSQL_HOST", "BK_PAAS_MYSQL_PASSWORD", "BK_PAAS_MYSQL_PORT", "BK_PAAS_MYSQL_USER", "BK_IAM_MYSQL_HOST", "BK_IAM_MYSQL_PASSWORD", "BK_IAM_MYSQL_PORT", "BK_IAM_MYSQL_USER", "BK_IAM_REDIS_MODE", "BK_IAM_REDIS_SENTINEL_ADDR", "BK_IAM_REDIS_SENTINEL_MASTER_NAME", "BK_IAM_REDIS_PASSWORD", "BK_IAM_REDIS_SENTINEL_PASSWORD", "BK_IAM_PRIVATE_ADDR", "BK_IAM_PRIVATE_URL", "BK_JOB_RABBITMQ_HOST", "BK_JOB_RABBITMQ_PORT", "BK_JOB_RABBITMQ_USERNAME", "BK_JOB_RABBITMQ_PASSWORD", "BK_JOB_RABBITMQ_VHOST"],
                'job': ["BK_JOB_MANAGE_MYSQL_HOST", "BK_JOB_MANAGE_MYSQL_PORT", "BK_JOB_MANAGE_MYSQL_USERNAME", "BK_JOB_MANAGE_MYSQL_PASSWORD", "BK_JOB_MANAGE_REDIS_MODE", "BK_JOB_MANAGE_REDIS_SENTINEL_MASTER", "BK_JOB_MANAGE_REDIS_SENTINEL_NODES", "BK_JOB_MANAGE_REDIS_CLUSTER_NODES", "BK_JOB_MANAGE_REDIS_HOST", "BK_JOB_MANAGE_REDIS_PORT", "BK_JOB_MANAGE_REDIS_PASSWORD", "BK_JOB_LOGSVR_MONGODB_URI", "BK_JOB_MANAGE_REDIS_SENTINEL_PASSWORD", ],
                'cmdb': ["BK_CMDB_REDIS_HOST", "BK_CMDB_REDIS_PORT","BK_CMDB_REDIS_SENTINEL_PASSWORD","BK_HOME", "BK_HTTP_SCHEMA", "BK_PAAS_PUBLIC_ADDR", "BK_PAAS_PRIVATE_ADDR", "BK_CMDB_ADMIN_PORT", "BK_CMDB_API_PORT", "BK_CMDB_AUTH_PORT", "BK_CMDB_CLOUD_PORT", "BK_CMDB_CORE_PORT", "BK_CMDB_DATACOLLECTION_PORT", "BK_CMDB_EVENT_PORT", "BK_CMDB_HOST_PORT", "BK_CMDB_OPERATION_PORT", "BK_CMDB_PROC_PORT", "BK_CMDB_SYNCHRONIZE_PORT", "BK_CMDB_TASK_PORT", "BK_CMDB_TOPO_PORT", "BK_CMDB_WEB_PORT", "BK_CMDB_ES7_REST_ADDR", "BK_CMDB_ES7_USER", "BK_CMDB_ES7_PASSWORD", "BK_CMDB_PUBLIC_URL", "BK_CMDB_API_HOST", "BK_CMDB_API_PRIVATE_ADDR", "BK_CMDB_API_URL", "BK_CMDB_APP_CODE", "BK_CMDB_APP_SECRET", "BK_IAM_PRIVATE_ADDR", "BK_CMDB_MONGODB_HOST", "BK_CMDB_MONGODB_PORT", "BK_CMDB_MONGODB_USERNAME", "BK_CMDB_MONGODB_PASSWORD", "BK_CMDB_REDIS_SENTINEL_HOST", "BK_CMDB_REDIS_SENTINEL_PORT", "BK_CMDB_REDIS_MASTER_NAME", "BK_CMDB_REDIS_PASSWORD", "BK_CMDB_ZK_ADDR",],
                'bknodeman': ["BK_NODEMAN_MYSQL_HOST", "BK_NODEMAN_MYSQL_NAME", "BK_NODEMAN_MYSQL_PASSWORD", "BK_NODEMAN_MYSQL_PORT", "BK_NODEMAN_MYSQL_USER", "BK_NODEMAN_RABBITMQ_HOST", "BK_NODEMAN_RABBITMQ_PORT", "BK_NODEMAN_RABBITMQ_USERNAME", "BK_NODEMAN_RABBITMQ_PASSWORD", "BK_NODEMAN_RABBITMQ_VHOST", "BK_NODEMAN_REDIS_SENTINEL_HOST", "BK_NODEMAN_REDIS_SENTINEL_PORT", "BK_NODEMAN_REDIS_SENTINEL_MASTER_NAME", "BK_NODEMAN_REDIS_PASSWORD", "BK_NODEMAN_USE_IAM","BK_NODEMAN_REDIS_SENTINEL_PASSWORD"],
                'bkssm': ["BK_SSM_REDIS_MODE","BK_SSM_MYSQL_HOST", "BK_SSM_MYSQL_PORT", "BK_SSM_MYSQL_USER", "BK_SSM_MYSQL_PASSWORD", "BK_SSM_MYSQL_NAME", "BK_PAAS_MYSQL_HOST", "BK_PAAS_MYSQL_PORT", "BK_PAAS_MYSQL_USER", "BK_PAAS_MYSQL_PASSWORD", "BK_PAAS_MYSQL_NAME", "BK_PAAS_PRIVATE_URL", "BK_SSM_REDIS_MODE", "BK_SSM_REDIS_HOST", "BK_SSM_REDIS_PASSWORD", "BK_SSM_REDIS_SENTINEL_MASTER_NAME", "BK_SSM_REDIS_SENTINEL_PASSWORD", "BK_SSM_REDIS_SENTINEL_ADDR",],
                "bkmonitorv3": ["BK_GSE_ZK_ADDR","BK_GSE_ZK_PORT","BK_MONITOR_MYSQL_HOST","BK_MONITOR_MYSQL_PASSWORD","BK_MONITOR_MYSQL_PORT","BK_MONITOR_MYSQL_USER","BK_PAAS_MYSQL_HOST","BK_PAAS_MYSQL_PASSWORD","BK_PAAS_MYSQL_PORT","BK_PAAS_MYSQL_USER","BK_MONITOR_RABBITMQ_HOST","BK_MONITOR_RABBITMQ_PORT","BK_MONITOR_RABBITMQ_VHOST","BK_MONITOR_RABBITMQ_USERNAME","BK_MONITOR_RABBITMQ_PASSWORD","BK_MONITOR_REDIS_SENTINEL_HOST","BK_MONITOR_REDIS_SENTINEL_PORT","BK_MONITOR_REDIS_SENTINEL_MASTER_NAME","BK_MONITOR_REDIS_PASSWORD","BK_MONITOR_REDIS_SENTINEL_PASSWORD","BK_MONITOR_ES_HOST","BK_MONITOR_ES_REST_PORT","BK_MONITOR_ES7_HOST","BK_MONITOR_ES7_PASSWORD","BK_MONITOR_ES7_REST_PORT","BK_MONITOR_ES7_TRANSPORT_PORT","BK_MONITOR_ES7_USER","BK_INFLUXDB_PROXY_HOST","BK_INFLUXDB_PROXY_PORT","BK_MONITOR_INFLUXDB_PORT","BK_MONITOR_INFLUXDB_USER","BK_MONITOR_INFLUXDB_PASSWORD"],
                "fta": ["BK_FTA_MYSQL_HOST","BK_FTA_MYSQL_PASSWORD","BK_FTA_MYSQL_PORT","BK_FTA_MYSQL_USER","BK_FTA_REDIS_HOST","BK_FTA_REDIS_MODE","BK_FTA_REDIS_PASSWORD","BK_FTA_REDIS_PORT","BK_FTA_REDIS_SENTINEL_HOST","BK_FTA_REDIS_SENTINEL_MASTER_NAME","BK_FTA_REDIS_SENTINEL_PORT"],
                "ci": ["BK_IAM_PRIVATE_URL","BK_CI_MYSQL_ADDR","BK_CI_MYSQL_PASSWORD","BK_CI_MYSQL_USER","BK_CI_RABBITMQ_ADDR","BK_CI_RABBITMQ_VHOST","BK_CI_RABBITMQ_USER","BK_CI_RABBITMQ_PASSWORD","BK_CI_ES_REST_ADDR","BK_CI_ES_REST_PORT","BK_CI_ES_CLUSTER_NAME","BK_CI_ES_USER","BK_CI_ES_PASSWORD","BK_CI_REDIS_HOST","BK_CI_REDIS_PORT","BK_CI_REDIS_DB","BK_CI_REDIS_PASSWORD"],
                "gse": ["BK_GSE_MONGODB_HOST", "BK_GSE_MONGODB_PORT", "BK_GSE_MONGODB_USERNAME", "BK_GSE_MONGODB_PASSWORD", "BK_GSE_REDIS_PASSWORD", "BK_GSE_REDIS_HOST", "BK_GSE_REDIS_PORT", "BK_GSE_ZK_ADDR", "BK_GSE_ZK_PORT", "BK_GSE_ZK_ADDR", "BK_GSE_ZK_TOKEN" ]
}

class API(object):
    '''
    description: BlueKing-V3 部署检查接口统一管理
    '''
    paas = {
        'login': '/login/',
        # 登陆
        'upload': '/saas/upload0/',
        # Saas文件上传
    },
    iam = {
        'ping' : 'ping/',
        'healthz': 'healthz',
    }

class Api_Check(object):
    
    def __init__(self, module: str, function: str):
        self.module =  module
        self.api = API() 

    def upload(self):
        HTTP_SCHEMA = os.environ.get('BK_HTTP_SCHEMA')
        paas_domain = os.environ.get('BK_PAAS_PUBLIC_ADDR')

    def login(self):
        url = self.api.paas['login']
        username = os.environ.get('BK_PAAS_ADMIN_USERNAME')
        password = os.environ.get('BK_PAAS_ADMIN_PASSWORD')

class Storage_Check(object):
    '''
    description: 存储相关通用检测函数
    '''    
    def __init__(self, username: str, password: str, ssh_port: int):
        self.api = API()
        self.username = username
        self.password = password
        self.ssh_port = ssh_port

    def common_env(self, env_list: list):
        '''
        description: 传入环境变量列表，返回真实环境变量字典 
        '''        
        result = {}
        for env in env_list:
            result[env] = os.environ.get(env) if os.environ.get(env) else None
        for env in environ_list['dbadmin']:
            result[env] = os.environ.get(env) if os.environ.get(env) else None
        return result
    
    def common_parsh_url(self, ):
        pass
    def get_lan_ip(self):
        
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        lan_ip=s.getsockname()[0]
        s.close()
        return "'%s'"%lan_ip

    def mysql_login_check(self, module: str, 
                        mysql_host: str, mysql_port: int, 
                        grant_user: str, grant_user_pass: str, grant_host: list,
                        if_install_mysql_client=True):
        '''
        description: 登陆到对应模块服务器，登陆目标mysql服务器
        '''
        password=self.username
        username=self.password
        mysql_port = int(mysql_port)

        for grant_ip in grant_host:
            commonad = "if ! which mysql;then sleep 10;fi;/usr/bin/mysql -u{} -p{} -P{} -h{} -Be 'select version()';/usr/bin/mysql -u{} -p{} -P{} -h{} -Be \"show variables like '%character_set_database%'\"".format(
                grant_user, grant_user_pass, mysql_port, mysql_host,
                grant_user, grant_user_pass, mysql_port, mysql_host)
            try:
                client = SSHClient()
                client.set_missing_host_key_policy(AutoAddPolicy())
                client.load_system_host_keys()
                if grant_ip == self.get_lan_ip():
                    client.connect(grant_ip.replace('\'',''), timeout=20,username=username, password=password, port=self.ssh_port)
                else:
                    client.connect(grant_ip.replace('\'',''), timeout=20, port=self.ssh_port)
                if if_install_mysql_client:
                    stdin1, stdout2, stderr2 = client.exec_command("yum install -q -y mysql-community-client")
                    if not stdout2:
                        logg.error("module -> [{}] host -> [{}] install mysql-community-client failed".format(module, stderr2.read()))
                stdin, stdout, stderr = client.exec_command(commonad)

                stdout1 = stdout.read()
                stderr1 = stderr.read().decode('utf-8')
                if stdout1:
                    logg.info("module -> [{}] mysql login check success! msg -> [{}], grant ip -> [{}], user -> [{}], pass -> [{}]".format(module, stdout1, grant_ip, grant_user, grant_user_pass))
                    # mysql version check
                    if re.search("5.7", stdout1.decode('utf-8')):
                        logg.info("module -> [{}] mysql version check success!".format(module))
                    else:
                        logg.error("module -> [{}] mysql version check failed! msg -> [{}]".format(module, stdout1))
                    if re.search("utf8", stdout1.decode("utf-8")):
                        logg.info("module -> [{}] mysql character check success! msg -> [{}]" .format(module, stdout1))
                    else:
                        logg.error("module -> [{}] mysql character check failed! msg -> [{}]" .format(module, stdout1))
                else:
                    logg.error("module -> [{}] mysql login check failed! msg -> [{}], grant ip -> [{}], user -> [{}], pass -> [{}]".format(module, stderr1, grant_ip, grant_user, grant_user_pass))
            except Exception as e:
                logg.error('module -> [{}] 免密登陆 -> [{}] 失败 err_msg -> [{}]'.format(module, grant_ip, traceback.format_exc()))
    
    def check_redis_by_get_mastername(self, module: str,
                                    single_host=None, single_port=None, single_password=None,
                                        sentinel_host=None, sentinel_port=None, sentinel_password=None,
                                        master_name = None,IS_SENTINEL=True
                                        ):

        if not single_port is None:
            single_port = int(single_port)
        if not sentinel_host is None:
            sentinel_port = int(sentinel_port)
        if not IS_SENTINEL:
            try:
                logg.info("module -> [{}] redis type is single" .format(module))
                redis_pool = redis.Redis(host = single_host, port = single_port, password = single_password)
                redis_version = redis_pool.execute_command('INFO')['redis_version']
                redis_pool.set('bk_deploy_check', 'Hollow, Blueking')
                logg.info('module -> [{}] check redis success ! singel node is -> {}:{} pass: {}'.format(module, single_host, single_port, single_password))
                if re.search("5.0.\d", redis_version):
                    logg.info("module -> [{}] redis version check success ! msg -> [{}]" .format(module, redis_version))
                else:
                    logg.error("module -> [{}] redis version check failed ! msg -> [{}]" .format(module, redis_version))
            except Exception as e:
                logg.error('module -> [{}] check redis failed ! error_msg {}'.format(module, e))
        else:
            logg.info("module -> [{}] redis type is sentinel" .format(module))
            try:
                sentinel = Sentinel([(sentinel_host, sentinel_port)], sentinel_kwargs={'password': sentinel_password})
                master = sentinel.discover_master(master_name)
                logg.info('module -> [{}] redis sentinel check success ! sentinel master node is -> {}'.format(module, master))
                slave = sentinel.discover_slaves(master_name)
                logg.info('module -> [{}] redis sentinel check success ! sentinel slave node is -> {}'.format(module, slave))
            except Exception as e:
                logg.error("module -> [{}] redis sentinel check failed! error_msg -> [{}]".format(module, e))

    def check_redis_cluster_health (self, module: str, 
                             redis_cluster_host=None, redis_cluster_port=None, redis_cluster_password=None
                            ):
        try:
            redis_client = redis.RedisCluster(
                host=redis_cluster_host,
                port=redis_cluster_port,
                password=redis_cluster_password,
                decode_responses=True
            )

            # 检查集群的健康状态
            cluster_info = redis_client.cluster_info()
            cluster_state = cluster_info.get('cluster_state')

            if cluster_state == 'ok':
                logg.info("module -> [{}] redis cluster state is healthy!".format(module))
            else:
                logg.error("module -> [{}] redis cluster state is not healthy! msg-> [{}]".format(module, cluster_state))

        except redis.exceptions.ClusterError as e:
            logg.error("module -> [{}] Error connecting to Redis Cluster:", str(e))


    def elasticsearch7_check(self,module: str, host: str, port: str, username=None, password=None):
        '''
        description: es7 连通性与版本测试
        '''        
        try:
            client = Elasticsearch(
                                    [host],
                                    http_auth=(username, password),
                                    scheme="http",
                                    port=port,
                                    sniffer_timeout=600,
                                    verify_certs=True,
                                    )
            if client.ping():
                logg.info("module -> [{}] es7 connectivity check success!".format(module))
                es_version = client.info()["version"]['number']
                if re.search('7.16.\d', es_version):
                    logg.info("module -> [{}] es7 version check success! msg-> [{}]".format(module, es_version))
                else:
                    logg.error("module -> [{}] es7 version check failed! msg-> [{}]".format(module, client.info()))
            else:
               logg.error("module -> [{}] es7 connectivity check failed! msg -> [{}]".format(module, "api: ping failed!"))
               return
        except Exception as e:
                logg.error("module -> [{}] es7 connectivity check failed! msg -> [{}]".format(module, e))
                return
        if module == "paas":
            time_today = time.strftime("%Y.%m.%d", time.localtime())
            index_name = "paas_app_log-{}".format(time_today)
            index_exists = client.indices.exists(index=index_name)
            if not index_exists:
                logg.error("module -> [{}] es7 index -> [{}] not exists! 请检查paas_plugins数据链路，如果没有部署paas_plugin,请忽略这条报错.".format(module, index_name))
            else:
                logg.info("module -> [{}] es7 index -> [{}]  exists!".format(module, index_name))

    def influxdb_check(self, host: str, port: int, module: str):
        '''
        description:  只检查ping接口返回是否是200
        '''
        port = int(port)
        url = 'http://{}:{}/ping?verbose=true'.format(host, port)
        try:
            result = requests.get(url)
            if result.status_code == 200:
                logg.info('module -> [{}] influxdb_check success! msg -> [{}]'.format(module, result.content))
            else:
                logg.error('module -> [{}] influxdb_check failed! msg -> [{}]'.format(module, result.content))
        except Exception as e:
            logg.error('module -> [{}] influxdb_check failed! msg -> [{}]'.format(module, e))
    
    def zookeeper_check(self, host: str, module: str, AUTH=None):
        '''
        description: zk连通性检查, cc gse-snapshot 节点检查
        '''
        try:
            zk = KazooClient(hosts=host)
            zk.start()
            logg.info("module -> [{}] zk connected".format(module,))
            if module == 'cmdb':
                try:
                    node_list = zk.get_children('/')
                    gse_node_list = zk.get('/gse/config/etc/dataserver/data/1001')
                    if 'cc' not  in node_list:
                        logg.error("module -> [{}] zookeeper_check failed! err_msg: node_list -> [{}]".format(module, node_list))
                    else:
                        logg.info("module -> [{}] zookeeper_check success! msg -> [{}]".format(module, node_list))
                    if len(gse_node_list) == 0:
                        logg.error("module -> [{}] zookeeper_check failed! err_msg -> len /gse/config/etc/dataserver/data/1001 is :[{}]".format(module, len(gse_node_list)))
                except Exception as e:
                    logg.error("module -> [{}] zookeeper_check failed msg -> [CMDB 已连接zk，但是节点还未注册] -> err_msg -> {}".format(module, e))
            elif module == 'gse':
                try:
                    auth_node = '/gse/config/server/dataserver'
                    node_list = zk.get_children(os.path.dirname(auth_node))
                    if 'dataserver' not in node_list: 
                        logg.error("gse node -> [{}/{}] not exist!, this node create by gse program!" .format(auth_node, 'dataserver'))
                        return
                    zk.add_auth('digest', AUTH)
                    cfg = zk.get(auth_node)
                    logg.info("module -> [{}], zk auth check success!".format(module))
                except NoAuthError:
                    logg.error('module -> [{}], zookeeper_check failed! err_msg -> [鉴权认证失败], password -> [{}]' .format('gse', AUTH))
        except Exception as e:
            logg.error("module -> [{}] zk check failed, msg: {}".format(module, e))
        zk.stop()

    def rabbitmq_check(self, host: str, port: int, username: str, password: str, vhost: str, module: str):
        '''
        description:  rabbbitmq 链接检查，只保证连通性
        '''        
        port=int(port)
        try: 
            url = 'amqp://{}:{}@{}:{}/{}'.format(username, password, host, port, vhost) 
            params = pika.URLParameters(url)
            params.socket_timeout = 5
            connection = pika.BlockingConnection(params)
            connection.close()
            logg.info('module -> [{}] rabbbitmq check success! '.format(module))
        except Exception as e:
            logg.error('module -> {} rabbitmq check failed! err_msg:->{} connetion_msg: -> [{}]'.format(module, e, url))
    
    def iam_ping(self, bk_iam_pravate_url: str, module: str):
        '''
        description:  从配置文件中获取iam地址，检查ping 和 health 接口
        '''        
        try:
            if not re.search('http', bk_iam_pravate_url):
                ping_url = 'http://{}/{}'.format(bk_iam_pravate_url,self.api.iam['ping'])
                health_url = 'http://{}/{}'.format(bk_iam_pravate_url,self.api.iam['healthz'])
            else:
                ping_url = '{}/{}'.format(bk_iam_pravate_url,self.api.iam['ping'])
                health_url = '{}/{}'.format(bk_iam_pravate_url,self.api.iam['healthz'])
            ping_result = requests.get(ping_url).content.decode('utf-8')
            health_result = requests.get(health_url).content.decode('utf-8')
            if json.loads(ping_result)['message'] == 'pong':
                logg.info('module -> [{}] iam ping url check success！ msg -> {}'.format(module, ping_result))
            else:
                logg.error("module -> [{}] iam config ping check failed! err_msg -> {}".format(module, ping_result))
            if health_result == 'ok':
                logg.info('module -> [{}] iam  health url check success！ msg -> {}'.format(module, health_result))
            else:
                logg.error("module -> [{}] iam config health check failed! err_msg -> {}".format(module, health_result))
        except Exception as e:
            logg.error("module -> [{}] iam config ping check failed! exception_msg -> [{}] iam_msg -> [{}]".format(module, e, ping_result))

    def redis_single_check(self, module: str, host: str, port: int, password: str):
        '''
        description:  单点redis校验
        '''
        try:
            port = int(port)
            pool = redis.Redis(host = host , port = port, password= password)
            version = pool.execute_command('INFO')['redis_version']
            pool.set('deploy_check1', 'Hollow, world')
            logg.info('module -> [{}] redis single slave node check success ! singel node is -> {}:{}'.format(module, host, port))
            if re.search("5.0.\d", version):
                logg.info("module -> [{}] redis single version check success ! msg -> [{}]" .format(module, version))
            else:
                logg.error("module -> [{}] redis single version check failed! msg -> [{}]". format(module, version))
        except Exception as e:
            logg.error("module -> [{}] redis single check failed! error_msg -> [{}]".format(module, e))

    def mysql_check(self, host: str, port: int, admin_username: str, admin_password: str, grant_user: str, ip: list, module: str):
        '''
        description: MySQL授权检查，原理是通过mysql-root账号查询授权账号是否授权对应ip地址（目前不能实现真正账号模拟登陆）
        '''
        port = int(port)
        try:
            connection = pymysql.connect(host = host, 
                                        port = port,
                                        password = admin_password,
                                        db = 'mysql',
                                        charset = 'utf8',
                                        user = admin_username,)
            cursor = connection.cursor()
            cursor.execute("select  Host from mysql.user where User='{}';".format(grant_user))
            ip_list = cursor.fetchall()
            if len(ip_list) == 0:
                logg.error("module -> [{}] mysql check failed! msg -> len({}) = 0".format(module, ip_list))
            if ip_list == (('',),):
                logg.info('module -> [{}] mysql check success! msg ->  注意 -> [{}]授权了任意ip地址访问, 不符合规范'.format(module, grant_user))
                return
            for _ip  in ip:
                if _ip not in [ str(x).replace('(','').replace(')','').replace('\'','').replace(',','') for x in ip_list]:
                    logg.error("module -> [{}] mysql check failed! user -> [{}] err_msg -> [{}] 未授权".format(module, grant_user, _ip))
                else:
                    logg.info("module -> [{}] mysql check success! -> [{}:{}] 已授权访问 -> [{}]".format(module, grant_user, _ip, host))
            
        except Exception as e:
            logg.error("module -> [{}] mysql check failed! msg -> [{}] \n提示:(1045: Access denied: ADMIN 密码错误) \n(1045: Unknown error 1045: 登陆错误ip地址)".format(module, traceback.format_exc()))

    def mongodb_check(self, host: str, port: int, username: str, password: str, database: str, module: str, timeout=40):
        '''
        description:  mogodb 账号读写检查, 网络超时问题未解决
        '''
        port = int(port)
        test_json = {
                        'id': '20170101',
                        'name': 'Jordan',
                        'age': 20,
                        'gender': 'male' }
        port = int(port)
        client = pymongo.MongoClient(host=host, port=port, connecttimeoutms=timeout)
        result =  client.the_database.authenticate(username, password, source=database,mechanism='SCRAM-SHA-1')
        url = "mongodb://{}:{}@{}:{}/?authSource={}&authMechanism=SCRAM-SHA-1".format(username, password, host, port, database)
        logg.debug(url)
        try:
            client = pymongo.MongoClient(url, connecttimeoutms=timeout)
            db = client[database]
            collection = db['test-collection']
            collection_list = db.collection_names()
            posts = db.posts
            post_id = posts.insert_one(test_json).inserted_id
            logg.info("module -> [{}] mongodb check success! ".format(module))
        except pymongo.errors.NotMasterError:
            client = pymongo.MongoClient(url, replicaSet="rs0",connecttimeoutms=timeout)
            logg.debug("mongodb database %s" % database)
            db = client[database]
            collection = db['test-collection']
            collection_list = db.collection_names()
            posts = db.posts
            post_id = posts.insert_one(test_json).inserted_id
            logg.info("module -> [{}] mongodb check success! ".format(module))
        except pymongo.errors.ServerSelectionTimeoutError:
            logg.error("module -> [{}] check mongo failed! msg -> [{} 网络超时]".format(module, host))
        except Exception as e:
            logg.error("module -> [{}] check mongo failed".format(e))
            
class Action(Storage_Check):
    '''
    description:  根据模块执行检查
    '''

    def gse(self):
        gse_check_env_dict = self.common_env(environ_list['gse'])
        self.mongodb_check(
                        host = gse_check_env_dict['BK_GSE_MONGODB_HOST'], 
                        port =  gse_check_env_dict['BK_GSE_MONGODB_PORT'], 
                        username = gse_check_env_dict['BK_GSE_MONGODB_USERNAME'],
                        password =  gse_check_env_dict['BK_GSE_MONGODB_PASSWORD'], 
                        database =  'gse',
                        module = "gse"
                        )

        self.zookeeper_check(
            host = gse_check_env_dict['BK_GSE_ZK_ADDR'],
            module = 'gse',
            AUTH = gse_check_env_dict['BK_GSE_ZK_TOKEN']
        )

        for ip in re.split(',', os.environ['BK_REDIS_CLUSTER_IP_COMMA'].replace('\'', "")):
            self.check_redis_cluster_health(
                module = "gse",
                redis_cluster_host = ip,
                redis_cluster_port = gse_check_env_dict['BK_GSE_REDIS_PORT'],
                redis_cluster_password = gse_check_env_dict['BK_GSE_REDIS_PASSWORD'],
            )

    def ci(self):
        ci_check_env_dict = self.common_env(environ_list['ci'])
        mysql_ip, mysql_port = re.split(":", ci_check_env_dict['BK_CI_MYSQL_ADDR'])
        ci_ip = re.split(',', os.environ['BK_CI_IP_COMMA'])
        self.mysql_login_check(
            module = 'ci',
            mysql_host = mysql_ip,
            mysql_port = mysql_port,
            grant_user = ci_check_env_dict['BK_CI_MYSQL_USER'],
            grant_user_pass = ci_check_env_dict['BK_CI_MYSQL_PASSWORD'],
            grant_host = ci_ip 
        )

        rabb_host, rabb_port = re.split(':', ci_check_env_dict['BK_CI_RABBITMQ_ADDR'])
        self.rabbitmq_check(
            module = 'ci',
            host = rabb_host,
            port = rabb_port,
            username = ci_check_env_dict['BK_CI_RABBITMQ_USER'],
            password = ci_check_env_dict['BK_CI_RABBITMQ_PASSWORD'],
            vhost = ci_check_env_dict['BK_CI_RABBITMQ_VHOST'],
        )

        self.elasticsearch7_check(
            module = 'ci',
            host = ci_check_env_dict['BK_CI_ES_REST_ADDR'],
            port = ci_check_env_dict["BK_CI_ES_REST_PORT"],
            username = ci_check_env_dict['BK_CI_ES_USER'],
            password = ci_check_env_dict['BK_CI_ES_PASSWORD']
        )

        self.check_redis_by_get_mastername(
            module = "ci",
            single_host = ci_check_env_dict['BK_CI_REDIS_HOST'],
            single_port = ci_check_env_dict['BK_CI_REDIS_PORT'],
            single_password = ci_check_env_dict['BK_CI_REDIS_PASSWORD'],
            IS_SENTINEL=False
        )

        self.iam_ping(
            bk_iam_pravate_url = ci_check_env_dict['BK_IAM_PRIVATE_URL'],
            module = "ci"
        )

    def fta(self):
        fta_check_env_dict =self.common_env(environ_list['fta'])
        is_sentinel = True if fta_check_env_dict['BK_FTA_REDIS_MODE'] == "sentinel" else False
        self.check_redis_by_get_mastername(
            module = 'fta',
            single_host = fta_check_env_dict['BK_FTA_REDIS_HOST'],
            single_port = fta_check_env_dict['BK_FTA_REDIS_PORT'],
            single_password = fta_check_env_dict['BK_FTA_REDIS_PASSWORD'],
            sentinel_port = fta_check_env_dict["BK_FTA_REDIS_SENTINEL_PORT"],
            sentinel_host = fta_check_env_dict["BK_FTA_REDIS_SENTINEL_HOST"],
            master_name = fta_check_env_dict['BK_FTA_REDIS_SENTINEL_MASTER_NAME'],
            IS_SENTINEL = is_sentinel
        )       

        fta_ip = re.split(',', os.environ['BK_FTA_IP_COMMA'])
        self.mysql_login_check(
            module = 'fta',
            mysql_host = fta_check_env_dict['BK_FTA_MYSQL_HOST'],
            mysql_port = fta_check_env_dict['BK_FTA_MYSQL_PORT'],
            grant_user = fta_check_env_dict['BK_FTA_MYSQL_USER'],
            grant_user_pass = fta_check_env_dict['BK_FTA_MYSQL_PASSWORD'],
            grant_host =  fta_ip
        )

    def bkmonitorv3(self):
        monitorv3_check_env_dict =self.common_env(environ_list['bkmonitorv3'])
        # redis
        self.check_redis_by_get_mastername(
            module = 'monitorv3',
            single_password = monitorv3_check_env_dict['BK_MONITOR_REDIS_PASSWORD'],
            sentinel_host = monitorv3_check_env_dict['BK_MONITOR_REDIS_SENTINEL_HOST'],
            sentinel_password = monitorv3_check_env_dict['BK_MONITOR_REDIS_SENTINEL_PASSWORD'],
            sentinel_port = monitorv3_check_env_dict['BK_MONITOR_REDIS_SENTINEL_PORT'],
            master_name = monitorv3_check_env_dict['BK_MONITOR_REDIS_SENTINEL_MASTER_NAME'],
        )       
        monitorv3_ip = re.split(',', os.environ['BK_MONITORV3_IP_COMMA'])
        self.mysql_login_check(
            module = 'monitorv3',
            mysql_host = monitorv3_check_env_dict['BK_PAAS_MYSQL_HOST'],
            mysql_port = monitorv3_check_env_dict['BK_PAAS_MYSQL_PORT'],
            grant_user = monitorv3_check_env_dict['BK_PAAS_MYSQL_USER'],
            grant_user_pass = monitorv3_check_env_dict['BK_PAAS_MYSQL_PASSWORD'],
            grant_host =  monitorv3_ip
        )
        self.mysql_login_check(
            module = 'monitorv3',
            mysql_host = monitorv3_check_env_dict['BK_MONITOR_MYSQL_HOST'],
            mysql_port = monitorv3_check_env_dict['BK_MONITOR_MYSQL_PORT'],
            grant_user = monitorv3_check_env_dict['BK_MONITOR_MYSQL_USER'],
            grant_user_pass = monitorv3_check_env_dict['BK_MONITOR_MYSQL_PASSWORD'],
            grant_host =  monitorv3_ip
        )
        self.rabbitmq_check(
            module = 'monitorv3',
            host = monitorv3_check_env_dict['BK_MONITOR_RABBITMQ_HOST'],
            port = monitorv3_check_env_dict['BK_MONITOR_RABBITMQ_PORT'],
            username = monitorv3_check_env_dict['BK_MONITOR_RABBITMQ_USERNAME'],
            password = monitorv3_check_env_dict['BK_MONITOR_RABBITMQ_PASSWORD'],
            vhost = monitorv3_check_env_dict['BK_MONITOR_RABBITMQ_VHOST'],
        )

        self.zookeeper_check(
            module = 'monitorv3',
            host = monitorv3_check_env_dict['BK_GSE_ZK_ADDR'] + ':' + monitorv3_check_env_dict['BK_GSE_ZK_PORT'],
        )
        self.elasticsearch7_check(
            module = 'monitorv3',
            host = monitorv3_check_env_dict['BK_MONITOR_ES7_HOST'],
            port = monitorv3_check_env_dict["BK_MONITOR_ES7_REST_PORT"],
            username = monitorv3_check_env_dict['BK_MONITOR_ES7_USER'],
            password = monitorv3_check_env_dict['BK_MONITOR_ES7_PASSWORD']
        )
        self.influxdb_check(
            host = os.environ.get('BK_INFLUXDB_IP0').replace('\'', "").replace('\"', ''), 
            port = monitorv3_check_env_dict['BK_MONITOR_INFLUXDB_PORT'],
            module = "monitorv3"
        )

    def ssm(self):
        ssm_check_env_dict = self.common_env(environ_list['bkssm'])
        # redis
        single_host, single_port = re.split(':', ssm_check_env_dict['BK_SSM_REDIS_SENTINEL_ADDR'])
        sentinel_host, sentinel_port = re.split(':', ssm_check_env_dict['BK_SSM_REDIS_SENTINEL_ADDR'])
        is_sentinel = False if  ssm_check_env_dict["BK_SSM_REDIS_MODE"] != "sentinel" else True
        self.check_redis_by_get_mastername(
            module = 'ssm',
            single_host = single_host,
            single_port = single_port,
            single_password = ssm_check_env_dict['BK_SSM_REDIS_PASSWORD'],
            sentinel_port = sentinel_port,
            sentinel_password = ssm_check_env_dict['BK_SSM_REDIS_SENTINEL_PASSWORD'],
            sentinel_host = sentinel_host,
            master_name = ssm_check_env_dict['BK_SSM_REDIS_SENTINEL_MASTER_NAME'],
            IS_SENTINEL = is_sentinel
        )
        # mysql 
        ssm_ip = re.split(',', os.environ['BK_SSM_IP_COMMA'])
        self.mysql_login_check(
            module = 'ssm',
            mysql_host = ssm_check_env_dict['BK_PAAS_MYSQL_HOST'],
            mysql_port = ssm_check_env_dict['BK_PAAS_MYSQL_PORT'],
            grant_user = ssm_check_env_dict['BK_PAAS_MYSQL_USER'],
            grant_user_pass = ssm_check_env_dict['BK_PAAS_MYSQL_PASSWORD'],
            grant_host =  ssm_ip
        )
        self.mysql_login_check(
            module = 'ssm',
            mysql_host = ssm_check_env_dict['BK_SSM_MYSQL_HOST'],
            mysql_port = ssm_check_env_dict['BK_SSM_MYSQL_PORT'],
            grant_user = ssm_check_env_dict['BK_SSM_MYSQL_USER'],
            grant_user_pass = ssm_check_env_dict['BK_SSM_MYSQL_PASSWORD'],
            grant_host =  ssm_ip
        )
        
    def bknodeman(self):
        nodeman_check_env_dict = self.common_env(environ_list['bknodeman'])
        # mysql check
        nodeman_ip = re.split(',', os.environ['BK_NODEMAN_IP_COMMA']) 
        self.mysql_login_check(
            module = 'bknodeman',
            mysql_host = nodeman_check_env_dict['BK_NODEMAN_MYSQL_HOST'],
            mysql_port = nodeman_check_env_dict['BK_NODEMAN_MYSQL_PORT'],
            grant_user = nodeman_check_env_dict['BK_NODEMAN_MYSQL_USER'],
            grant_host =  nodeman_ip,
            grant_user_pass = nodeman_check_env_dict['BK_NODEMAN_MYSQL_PASSWORD']
        )
        self.rabbitmq_check(
            host = nodeman_check_env_dict['BK_NODEMAN_RABBITMQ_HOST'],
            port = nodeman_check_env_dict['BK_NODEMAN_RABBITMQ_PORT'],
            username = nodeman_check_env_dict['BK_NODEMAN_RABBITMQ_USERNAME'],
            password = nodeman_check_env_dict['BK_NODEMAN_RABBITMQ_PASSWORD'],
            vhost = nodeman_check_env_dict['BK_NODEMAN_RABBITMQ_VHOST'],
            module = 'bknodeman'
        )
        is_sentinel = False if nodeman_check_env_dict["BK_NODEMAN_REDIS_SENTINEL_MASTER_NAME"] == None else True
        self.check_redis_by_get_mastername(
            module = 'bknodeman',
            sentinel_password = nodeman_check_env_dict['BK_NODEMAN_REDIS_SENTINEL_PASSWORD'],
            sentinel_host = nodeman_check_env_dict['BK_NODEMAN_REDIS_SENTINEL_HOST'],
            sentinel_port = nodeman_check_env_dict['BK_NODEMAN_REDIS_SENTINEL_PORT'],
            master_name = nodeman_check_env_dict['BK_NODEMAN_REDIS_SENTINEL_MASTER_NAME'],
            IS_SENTINEL = is_sentinel
        )
    
    def paas(self):
        paas_check_env_dict = self.common_env(environ_list['paas'])
        # redis single check
        self.check_redis_by_get_mastername(
            module = "paas",
            single_host = paas_check_env_dict['BK_PAAS_REDIS_HOST'],
            single_port = paas_check_env_dict['BK_PAAS_REDIS_PORT'],
            single_password = paas_check_env_dict['BK_PAAS_REDIS_PASSWORD'],
            IS_SENTINEL=False
        )
        try:
            # self.mysql_check(
            #     host = paas_check_env_dict['BK_PAAS_MYSQL_HOST'],
            #     port = paas_check_env_dict['BK_PAAS_MYSQL_PORT'],
            #     admin_password = paas_check_env_dict['BK_MYSQL_ADMIN_PASSWORD'],
            #     admin_username = paas_check_env_dict['BK_MYSQL_ADMIN_USER'],
            #     grant_user = paas_check_env_dict['BK_PAAS_MYSQL_USER'],
            #     ip = re.split(',', str(os.environ['BK_PAAS_IP_COMMA']).replace('\'','')),
            #     module = 'paas'
            # )
            paas_ip = re.split(',', os.environ['BK_PAAS_IP_COMMA'].replace('\'',''))
            self.mysql_login_check(
                module = 'paas',
                mysql_host = paas_check_env_dict['BK_PAAS_MYSQL_HOST'],
                mysql_port = paas_check_env_dict['BK_PAAS_MYSQL_PORT'],
                grant_user = paas_check_env_dict['BK_PAAS_MYSQL_USER'],
                grant_user_pass = paas_check_env_dict['BK_PAAS_MYSQL_PASSWORD'],
                grant_host = paas_ip,
            )
        except Exception as e:
            logg.error("module -> [{}] mysql grant check failed! msg -> [{}]".format("paas", traceback.format_exc()))
        
        es7_addr = paas_check_env_dict['BK_PAAS_ES7_ADDR'] 
        username, password = es7_addr.split('@')[0].split(':')
        host, port = es7_addr.split('@')[1].split(':')

        self.elasticsearch7_check(
            host = host,
            port = port,
            module = "paas",
            username = username,
            password = password
        )

    def usermgr(self):
        usermgr_check_env_dict = self.common_env(environ_list['usermgr'])
        # rabbitmq 链接测试
        self.rabbitmq_check(
                        usermgr_check_env_dict['BK_USERMGR_RABBITMQ_HOST'],
                        int(usermgr_check_env_dict['BK_USERMGR_RABBITMQ_PORT']),
                        usermgr_check_env_dict['BK_USERMGR_RABBITMQ_USERNAME'],
                        usermgr_check_env_dict['BK_USERMGR_RABBITMQ_PASSWORD'],
                        usermgr_check_env_dict['BK_USERMGR_RABBITMQ_VHOST'],
                        'usermgr')
        # usermg 从配置型请求iam
        self.iam_ping(usermgr_check_env_dict['BK_IAM_PRIVATE_URL'], "usermgr")
        # # mysql check
        # try:
        #     self.mysql_check(
        #         host = usermgr_check_env_dict['BK_USERMGR_MYSQL_HOST'],
        #         port = usermgr_check_env_dict['BK_USERMGR_MYSQL_PORT'],
        #         admin_password = usermgr_check_env_dict['BK_MYSQL_ADMIN_PASSWORD'],
        #         admin_username = usermgr_check_env_dict['BK_MYSQL_ADMIN_USER'],
        #         grant_user = usermgr_check_env_dict['BK_USERMGR_MYSQL_USER'],
        #         ip = re.split(',', os.environ['BK_USERMGR_IP_COMMA'].replace('\'',"")),
        #         module = "usermgr"
        #     )
        # except Exception as e:
        #     logg.error("module -> [{}] mysql check failed msg -> [{}]".format("usermgr", e))

        # usermgr mysql login check
        usermgr_ip = re.split(",", os.environ['BK_USERMGR_IP_COMMA'])
        self.mysql_login_check(
            module = "iam", 
            mysql_host = usermgr_check_env_dict['BK_USERMGR_MYSQL_HOST'],
            mysql_port = usermgr_check_env_dict['BK_USERMGR_MYSQL_PORT'],
            grant_user = usermgr_check_env_dict['BK_USERMGR_MYSQL_USER'],
            grant_user_pass = usermgr_check_env_dict['BK_USERMGR_MYSQL_PASSWORD'],
            grant_host = usermgr_ip
        )
    
    def bkiam(self):
        '''
        description:  ce ee check 要分开
        '''
        iam_check_env_dict = self.common_env(environ_list['bkiam'])
        # redis_sentinel_check
        sentinel_host, sentinel_port = re.split(':', iam_check_env_dict['BK_IAM_REDIS_SENTINEL_ADDR'])
        single_host, single_port = re.split(':', iam_check_env_dict['BK_IAM_REDIS_SENTINEL_ADDR'])
        is_sentinel=True if iam_check_env_dict['BK_IAM_REDIS_MODE'] == 'sentinel' else False
        self.check_redis_by_get_mastername(
            sentinel_host = sentinel_host,
            sentinel_port = sentinel_port,
            master_name = iam_check_env_dict['BK_IAM_REDIS_SENTINEL_MASTER_NAME'],
            sentinel_password= iam_check_env_dict['BK_IAM_REDIS_SENTINEL_PASSWORD'],
            single_password = iam_check_env_dict['BK_IAM_REDIS_PASSWORD'],
            single_host = single_host,
            single_port = single_port,
            IS_SENTINEL = is_sentinel,
            module = 'iam'
        )
        # try:
        # # iam mysql grant check
        #     self.mysql_check(
        #         admin_username = iam_check_env_dict['BK_MYSQL_ADMIN_USER'],
        #         admin_password = iam_check_env_dict['BK_MYSQL_ADMIN_PASSWORD'],
        #         host = iam_check_env_dict['BK_IAM_MYSQL_HOST'],
        #         port = int(iam_check_env_dict['BK_IAM_MYSQL_PORT']),
        #         grant_user = iam_check_env_dict['BK_IAM_MYSQL_USER'],
        #         module = "iam",
        #         ip = re.split(',', os.environ['BK_IAM_IP_COMMA'].replace('\'',""))
        #     )
        #     # paas mysql check
        #     self.mysql_check(
        #         admin_username = iam_check_env_dict['BK_MYSQL_ADMIN_USER'],
        #         admin_password = iam_check_env_dict['BK_MYSQL_ADMIN_PASSWORD'],
        #         host = iam_check_env_dict['BK_PAAS_MYSQL_HOST'],
        #         port = int(iam_check_env_dict['BK_PAAS_MYSQL_PORT']),
        #         grant_user = iam_check_env_dict['BK_PAAS_MYSQL_USER'],
        #         module = "iam",
        #         ip = re.split(",", os.environ['BK_IAM_IP_COMMA'].replace('\'',""))
        #     )
        # except KeyError as e:
        #     logg.error("module -> [{}] -> 获取环境变量失败 -> msg [{}]".format("iam", e))

        # iam mysql login check
        iam_ip = re.split(",", os.environ['BK_IAM_IP_COMMA'])
        self.mysql_login_check(
            module = "iam", 
            mysql_host = iam_check_env_dict['BK_IAM_MYSQL_HOST'],
            mysql_port = iam_check_env_dict['BK_IAM_MYSQL_PORT'],
            grant_user = iam_check_env_dict['BK_IAM_MYSQL_USER'],
            grant_user_pass = iam_check_env_dict['BK_IAM_MYSQL_PASSWORD'],
            grant_host = iam_ip
        )
        self.mysql_login_check(
            module = "iam", 
            mysql_host = iam_check_env_dict['BK_PAAS_MYSQL_HOST'],
            mysql_port = iam_check_env_dict['BK_PAAS_MYSQL_PORT'],
            grant_user = iam_check_env_dict['BK_PAAS_MYSQL_USER'],
            grant_user_pass = iam_check_env_dict['BK_PAAS_MYSQL_PASSWORD'],
            grant_host = iam_ip
        )

    def cmdb(self):
        cmdb_check_env_dict = self.common_env(environ_list['cmdb'])
        # iam check
        self.iam_ping(
            bk_iam_pravate_url = cmdb_check_env_dict['BK_IAM_PRIVATE_ADDR'],
            module = "cmdb"
        )

        # redis sentinel check
        self.check_redis_by_get_mastername(
            sentinel_host = cmdb_check_env_dict['BK_CMDB_REDIS_SENTINEL_HOST'],
            sentinel_port =  cmdb_check_env_dict["BK_CMDB_REDIS_SENTINEL_PORT"],
            master_name = cmdb_check_env_dict['BK_CMDB_REDIS_MASTER_NAME'],
            sentinel_password = cmdb_check_env_dict["BK_CMDB_REDIS_SENTINEL_PASSWORD"],
            module = "cmdb",
            single_password = cmdb_check_env_dict['BK_CMDB_REDIS_PASSWORD'],
            single_host = cmdb_check_env_dict['BK_CMDB_REDIS_HOST'],
            single_port = cmdb_check_env_dict['BK_CMDB_REDIS_PORT'], 
        ) 

        # cmdb mongodb check
        self.mongodb_check(
            host = cmdb_check_env_dict['BK_CMDB_MONGODB_HOST'],
            port = cmdb_check_env_dict['BK_CMDB_MONGODB_PORT'],
            username = cmdb_check_env_dict['BK_CMDB_MONGODB_USERNAME'],
            password = cmdb_check_env_dict['BK_CMDB_MONGODB_PASSWORD'],
            database = "cmdb" ,
            module = 'cmdb'
        )

        # Check zk
        # zk_host, zk_port  = re.split(":", cmdb_check_env_dict['BK_CMDB_ZK_ADDR'])
        zk_hosts = cmdb_check_env_dict['BK_CMDB_ZK_ADDR']
        self.zookeeper_check(
            host = zk_hosts,
            module = 'cmdb'
        )

    def job(self):
        job_check_env_dict = self.common_env(environ_list['job'])
        job_ip = re.split(',', os.environ['BK_JOB_IP_COMMA'].replace('\'',""))
        # check mongo 
        url = job_check_env_dict['BK_JOB_LOGSVR_MONGODB_URI']
        part1, part2  = re.split("@",re.split("//", url)[1])
        user, password = re.split(':', part1)
        host, port = re.split(':', re.split('/', part2)[0])
        database = re.split('\\\?', re.split('/', part2)[1])[0]
        # job mongo check
        self.mongodb_check(
            host = host, 
            port = int(port),
            username = user,
            password = password,
            database = database,
            module = 'job' 
        )
        # job manage redis sentinel check
        manage_sentinel_host, manage_sentinel_port= re.split(":", job_check_env_dict["BK_JOB_MANAGE_REDIS_SENTINEL_NODES"])
        is_sentinel = True if job_check_env_dict['BK_JOB_MANAGE_REDIS_SENTINEL_MASTER'] != 'None' else False
        self.check_redis_by_get_mastername(
            sentinel_host = manage_sentinel_host,
            sentinel_port = manage_sentinel_port,
            master_name = job_check_env_dict['BK_JOB_MANAGE_REDIS_SENTINEL_MASTER'],
            sentinel_password = job_check_env_dict["BK_JOB_MANAGE_REDIS_SENTINEL_PASSWORD"],
            IS_SENTINEL = is_sentinel,
            module = 'job',

        )

        # mysql
        self.mysql_login_check(
            module = "job-manage", 
            mysql_host = job_check_env_dict['BK_JOB_MANAGE_MYSQL_HOST'],
            mysql_port = job_check_env_dict['BK_JOB_MANAGE_MYSQL_PORT'],
            grant_user = job_check_env_dict['BK_JOB_MANAGE_MYSQL_USERNAME'],
            grant_user_pass = job_check_env_dict['BK_JOB_MANAGE_MYSQL_PASSWORD'],
            grant_host = job_ip 
        )

        # 太麻烦了rabbitmq检查一次
        self.rabbitmq_check(
            host = job_check_env_dict['BK_JOB_RABBITMQ_HOST'],
            port = job_check_env_dict['BK_JOB_RABBITMQ_PORT'],
            username = job_check_env_dict['BK_JOB_RABBITMQ_USERNAME'],
            password = job_check_env_dict['BK_JOB_RABBITMQ_PASSWORD'],
            vhost = job_check_env_dict['BK_JOB_RABBITMQ_VHOST'],
            module = 'job'
        )
        
class ENV(object):

    '''
    description:  导入环境变量类
    param {check_module_name}  ps: cmdb,job,paas
    param {config_directory}   ps: /data/install/bin/04-final/
    '''    
    def __init__(self, config_directory: str, check_modules_name: str):
        if check_modules_name == 'iam': check_modules_name = "bkiam"
        self.config_directory = config_directory
        self.check_modules_name = check_modules_name
        self.environ_list = environ_list
        self.support_check_module = ['paas', 'bkiam', 'usermgr', 'bknodeman', 'ssm','bkmonitorv3', "cmdb", 'bklog', 'job', 'fta', "ci", "gse"]

    def load_dir_all_env(self):
        '''
        description: 导入指定文件夹下的环境变量
        '''        
        for module in re.split(',',self.check_modules_name):
            if module not in self.support_check_module:
                logg.error('模块 -> {} 不包含在脚本支持的范围 -> {} 中'
                                .format(module, self.support_check_module))
                func = Action()
                support_modules = []
                for _m in self.support_check_module:
                    try:
                        if getattr(func, _m):
                            support_modules.append(_m)
                    except Exception as e:
                        pass
                logg.error('当前脚本支持的模块有 -> {}'.format(support_modules))
                sys.exit(1)
        
        if not os.path.isdir(self.config_directory):
            logg.error("目录不存在 -> {} ".format(self.config_directory))
            sys.exit(1)
        real_env_file = ["%s.env" % env  for env in re.split(',',self.check_modules_name)]
        for env_file in real_env_file:
            if env_file  not in  os.listdir(self.config_directory):
                logg.error("文件->{},不存在目录->{}中".format(env_file, self.config_directory,))
                sys.exit(1)
        for env_file in os.listdir(self.config_directory):
            logg.error(env_file)
            with open('{}/{}'.format(self.config_directory, env_file), 'r') as e:
                for line in e:
                    # 去除空行
                    if len(line.strip())  == 0:
                        continue
                    # 去除注释
                    if re.search('^(#|\[)', line.strip()):
                        continue
                    # 去除不带=的行
                    if not re.search('=', line):
                        continue
                    # 去除换行符
                    line = line.replace('\n', '').replace('\r', '')
                    # 导入当前环境变量
                    env_key, env_value = re.split('=', line , maxsplit=1)
                    os.environ[env_key] = env_value
                    
        # 检查硬编码的变量是否为空，这些变量比较重要，需要为非空 
        for module in re.split(',', self.check_modules_name):
            self.check_environment(module)

    def load_single_file_env(self):
        '''
        description: 导入指定文件环境变量
        '''        
        for module in re.split(',',self.check_modules_name):
            if module not in self.support_check_module:
                logg.error('模块 -> [{}] 不包含在脚本预期支持的范围 -> {} 中'
                                .format(module, self.support_check_module))
                func = Action()
                support_modules = []
                for _m in self.support_check_module:
                    try:
                        if getattr(func, _m):
                            support_modules.append(_m)
                    except Exception as e:
                        pass
                logg.error('当前脚本支持的模块有 -> {}'.format(support_modules))
                sys.exit(1)
        
        if not os.path.isdir(self.config_directory):
            logg.error("目录不存在 -> {} ".format(self.config_directory))
            sys.exit(1)
        real_env_file = ["%s.env" % env  for env in re.split(',',self.check_modules_name)]
        for env_file in real_env_file:
            if env_file == "iam.env": env_file = "bkiam.env"
            if env_file == "ssm.env": env_file = "bkssm.env"
            if env_file  not in  os.listdir(self.config_directory):
                logg.error("文件->{},不存在目录->{}中".format(env_file, self.config_directory,))
                sys.exit(1)
        if re.search("ssm", self.check_modules_name):
            self.check_modules_name = self.check_modules_name.replace("ssm", "bkssm") 
        real_env_file_path = ["%s/%s.env" %(self.config_directory, env)  for env in re.split(',',self.check_modules_name)]
        for env_file in real_env_file_path:
            with open(env_file, 'r') as e:
                for line in e:
                    # 去除空行
                    if len(line.strip())  == 0:
                        continue
                    # 去除注释
                    if re.search('^(#|\[)', line.strip()):
                        continue
                    # 去除不带=的行
                    if not re.search('=', line):
                        continue
                    # 去除换行符
                    line = line.replace('\n', '').replace('\r', '')
                    # 导入当前环境变量
                    env_key, env_value = re.split('=', line , maxsplit=1)
                    os.environ[env_key] = env_value
                    
        # 检查硬编码的变量是否为空，这些变量比较重要，需要为非空 
        for module in re.split(',', self.check_modules_name):
            self.check_environment(module)

    def load_specified_file_env(self, env_file: str, host_env_file='/data/install/bin/02-dynamic/hosts.env'):
        '''
        description: 导入指定文件环境变量
        '''        
        for file in [env_file, host_env_file]:
            with open(file, 'r') as e:
                for line in e:
                    # 去除空行
                    if len(line.strip())  == 0:
                        continue
                    # 去除注释
                    if re.search('^(#|\[)', line.strip()):
                        continue
                    # 去除不带=的行
                    if not re.search('=', line):
                        continue
                    # 去除换行符
                    line = line.replace('\n', '').replace('\r', '')
                    # 导入当前环境变量
                    env_key, env_value = re.split('=', line , maxsplit=1)
                    os.environ[env_key] = env_value
                    
    def check_environment(self, module: str):
        '''
        description:  根据模块检查是否有空变量
        '''        
        try:
            environs = self.environ_list[module]
        except:
            logg.error("模块 -> {} 硬性检查变量未定义".format(module))
        for env in environs: 
            try:
               if len(os.environ.get(env)) == 0:
                   logg.error('env -> {} is None!'.format(env))
            except:
                   logg.error('env -> {} is None!'.format(env))

class Log:
    def __init__(self):
        self.log_colors_config = {
            'DEBUG': 'cyan',
            'INFO': 'green',
            'WARNING': 'yellow',
            'ERROR': 'red',
            'CRITICAL': 'red',
        }
        self.logger = logging.getLogger()
        self.logger.setLevel(logging.INFO)
        self.formatter = colorlog.ColoredFormatter(
            '%(log_color)s[%(asctime)s] [%(filename)s] [%(levelname)s]- %(message)s',
            log_colors=self.log_colors_config)  # 日志输出格式

    def TimeStampToTime(self, timestamp):
        """格式化时间"""
        timeStruct = time.localtime(timestamp)
        return str(time.strftime('%Y-%m-%d', timeStruct))

    def __console(self, level, message):
        # 创建一个StreamHandler,用于输出到控制台
        ch = colorlog.StreamHandler()
        ch.setLevel(logging.DEBUG)
        ch.setFormatter(self.formatter)
        self.logger.addHandler(ch)

        if level == 'info':
            self.logger.info(message)
        elif level == 'debug':
            self.logger.debug(message)
        elif level == 'warning':
            self.logger.warning(message)
        elif level == 'error':
            self.logger.error(message)
        # 这两行代码是为了避免日志输出重复问题
        self.logger.removeHandler(ch)

        logging.getLogger("pika").propagate = False
        logging.getLogger("kazoo").propagate = False
        logging.getLogger("elasticsearch").propagate = False
        logging.getLogger("paramiko").propagate = False

    def debug(self, message):
        self.__console('debug', message)

    def info(self, message):
        self.__console('info', message)

    def warning(self, message):
        self.__console('warning', message)

    def error(self, message):
        self.__console('error', message)  

class StepEmphasize:
    '''
    description: 强调检查步骤
    '''
    def __init__(self, module):
        self.module = module

    def get_formatted_title(self):
        current_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
        formatted_title = f"{current_time} checking 【{self.module}】module related information"
        return formatted_title

    def print_step_title(self):
        formatted_title = self.get_formatted_title()
        colored_title = f"\033[44m {formatted_title}\033[0m"
        print(colored_title)

if __name__ == "__main__":
    p =  argparse.ArgumentParser()
    p.add_argument('-d', action='store', dest='env_dir', help='final directory')
    p.add_argument('-u', action='store', dest='ssh_username', default="root", help='ssh username')
    p.add_argument('-p', action='store', dest='ssh_password', help='ssh password') 
    p.add_argument('-P', action='store', dest='ssh_port', help='ssh password', default=22) 
    p.add_argument('-m', action='store', dest='module', help="检查的模块: ps: cmdb,job,paas")
    p.add_argument('-a', action='store', dest="specified_env_file", default="/data/install/bin/01-generate/dbadmin.env", help="like dbadmin.env")
    p.add_argument('-o', action='store', dest="host_env_file", default="/data/install/bin/02-dynamic/hosts.env", help="hosts env file")
    args = p.parse_args()

    # 自定义颜色日志
    logg = Log()

    # 加载hosts, dbadmin ,有默认值 可不传入
    env = ENV(args.env_dir, args.module)
    env.load_specified_file_env(args.specified_env_file, args.host_env_file)

    # 加载指定模块对应的final env文件
    env.load_single_file_env()
    action = Action(args.ssh_password, args.ssh_username, args.ssh_port)
    

    # 根据函数名称执行校验
    for m in re.split(',', args.module):
        step=StepEmphasize(m)
        step.print_step_title()
        getattr(action, m)()
