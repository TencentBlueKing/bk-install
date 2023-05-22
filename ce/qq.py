#!/opt/py36/bin/python
# -*- coding: utf8
from builtins import print
import argparse
import sys
import yaml
import re
import shutil
import os

TMP_DIR='/tmp/bk_project'

class Config:

    @classmethod
    def project_cache(cls, project_yaml):
        P_TMP_DIR = os.path.split(project_yaml)[0].replace(re.search('^(/[a-z0-9]+)', project_yaml).group(), TMP_DIR)
        P_TMP_FILE_PATH = os.path.join(P_TMP_DIR, os.path.split(project_yaml)[1])
        if os.path.exists(project_yaml):
            if not os.path.exists(P_TMP_DIR):
                os.makedirs(P_TMP_DIR, 755) 
            shutil.copy(project_yaml, P_TMP_FILE_PATH)
            return project_yaml
        else:
            if os.path.exists(P_TMP_FILE_PATH):
                return P_TMP_FILE_PATH
            else:
                raise FileNotFoundError('Project file -> [{}] not exist.'.format(project_yaml))

    @classmethod
    def config(cls, hosts_env, port_yaml, project_yaml=None, ip_parse=False):
        port_env = yaml.load(open(port_yaml), Loader=yaml.FullLoader)
        with open(hosts_env, 'r') as e:
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
                comma_env_key, env_value = re.split('=', line , maxsplit=1)
                os.environ[comma_env_key] = env_value
        if project_yaml is not None:
            project_yaml = Config.project_cache(project_yaml)
            projects = []
            statement = []
            statement.append("declare -A _project_dir _language _user _project_port _project_ip _project_consul _projects")
            # 返回跟当前模块相关的变量
            for i in yaml.load(open(project_yaml), Loader=yaml.FullLoader):
        
                if 'user' not in i:
                    i['user'] = 'blueking'
                if 'group' not in i:
                    i['group'] = 'blueking'

                # 特殊处理名称不统一问题
                # TODO: appo appt 问题未解决
                module = i['module']
                if module == 'open_paas': module = 'paas'
                if module == 'bkmonitorv3': module = 'monitorv3'
                if module == 'bkssm': module = 'ssm'
                if module == 'bkiam': module = 'iam'
                if module == 'paas_agent' : module = 'appo'
                if module == 'bklog' : module = 'log'
                if module == 'bkiam_search_engine' : module = 'iam_search_engine'
                if module == 'bkauth': module = 'auth'

                project = i['name']
                projects.append(project)

                # 端口为None时返回端口为空字符串, port只要匹配其之一即可
                try:
                    port = port_env[module][i['name']]['port'] 
                except Exception:
                    port = port_env[i['module']][i['name']]['port'] 

                if port is None: port = ''

                comma_env_key = "BK_{}_{}_IP_COMMA".format(module, i['name']).replace('-', '_').upper()
                # consul为None时返回端口为空字符串,只要匹配其之一即可
                try:
                    # 去除行尾多余的"."
                    consul = port_env[module][i['name']]['consul'].strip('.')
                except Exception:
                    # consul为空时返回空字符串
                    try:
                        consul = port_env[i['module']][i['name']]['consul'].strip('.')
                    except Exception:
                        consul = ''
                # 未存在的project ip 设置为 module ip
                try:
                    project_ip  =  os.environ[comma_env_key]
                except Exception:
                    # 特例处理 为了兼容不统一名称
                    if module == 'bknodeman': module = 'nodeman'
                    comma_env_key = "BK_{}_IP_COMMA".format(module).replace('-', '_').upper()
                    project_ip = os.environ[comma_env_key]

                statement.append('_project_dir["{},{}"]={}'.format(i['module'],i['name'],i['project_dir'].strip('/')))
                statement.append('_language["{},{}"]={}'.format(i['module'],i['name'],i['language']))
                statement.append('_user["{},{}"]={}/{}'.format(i['module'],i['name'],i['user'],i['group']))
                statement.append('_project_port["{},{}"]={}'.format(i['module'],i['name'],port))
                statement.append('_project_consul["{},{}"]={}'.format(i['module'],i['name'],consul))
                # 兼容指定ip  匹配不到预设值则返回所有ip
                if not ip_parse or re.search('^[a-z]', ip_parse) :
                    statement.append('_project_ip["{},{}"]={}'.format(i['module'],i['name'],project_ip))
                else:
                    if re.search('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', ip_parse):
                        statement.append('_project_ip["{},{}"]={}'.format(i['module'],i['name'], ip_parse))
                    # else:
                    #     statement.append('_project_ip["{},{}"]={}'.format(i['module'],i['name'],project_ip))
            if 'synchronize' in projects:
                projects.remove('synchronize') # 特例: 去掉cmdb的 syncchronize 状态展示
            statement.append('_projects["{}"]="{}"'.format(module," ".join(projects)))
        else:
            pass
        return '\n'.join(statement)

    @classmethod
    def storage(cls, port_yaml):
        statement = []
        statement.append("declare -A _project_port _project_consul _project_name _projects")
        storage_list = ['redis', 'mysql', 'pypi', 'yum', "influxdb", "es7", "zk", "rabbitmq", "mongodb", "kafka", "beanstalk", "etcd"]
        port_env = yaml.load(open(port_yaml), Loader=yaml.FullLoader)
        for storage in storage_list:
            projects = list(port_env[storage].keys())
            projects = ' '.join(projects).replace('default', '')
            if storage == 'redis_sentinel': 
                name = "master_name"
            else:
                name = "name"
            for module in port_env[storage].keys():
                try:
                    statement.append('_project_port["{},{}"]={}'.format(storage, module, port_env[storage][module]['port']))
                    statement.append('_project_consul["{},{}"]={}'.format(storage, module, port_env[storage][module]['consul']))
                    statement.append('_project_name["{},{}"]={}'.format(storage, module, port_env[storage][module][name]))
                    statement.append('_projects["{}"]="{}"'.format(storage,projects))
                except Exception:
                    pass
        return '\n'.join(statement)


if  __name__ == '__main__':
    dirname, _ = os.path.split(os.path.abspath(sys.argv[0]))
    default_host_env="%s/bin/02-dynamic/hosts.env" % dirname
    p =  argparse.ArgumentParser()
    p.add_argument('-p', action='store', dest='project_yaml', help='final directory')
    p.add_argument('-P', action='store', dest='port_yaml', help='final directory')
    p.add_argument('-H', action='store', dest='host_env', default=default_host_env, help='final directory')
    p.add_argument('-s', action='store_true', dest='storage_parse')
    p.add_argument('-i', action='store', dest='ip_parse', default=False)
    args = p.parse_args()

    if not args.storage_parse:
        result = Config.config(args.host_env, args.port_yaml, args.project_yaml, args.ip_parse)
    else:
        result = Config.storage(args.port_yaml)
    print(result)
