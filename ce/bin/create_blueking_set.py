#!/opt/py36/bin/python
# -*- coding: utf8
import time
import argparse
import requests
import json
import sys
import re
import logging

class Message(object):
    list_biz_hosts = "/api/c/compapi/v2/cc/list_biz_hosts/"
    list_set_template = "/api/c/compapi/v2/cc/list_set_template/"
    create_set =  "/api/c/compapi/v2/cc/create_set/"
    find_set_batch = "/api/c/compapi/v2/cc/find_set_batch/"
    search_biz_inst_topo = "/api/c/compapi/v2/cc/search_biz_inst_topo/"
    batch_delete_set = "/api/c/compapi/v2/cc/batch_delete_set/"
    batch_delete_inst = "/api/c/compapi/v2/cc/batch_delete_inst/"
    batch_create_proc_template= "/api/c/compapi/v2/cc/batch_create_proc_template/"
    list_service_template = "/api/c/compapi/v2/cc/list_service_template/"
    CREATE_SERVICE_TEMPLATE ="/api/c/compapi/v2/cc/create_service_template/"
    update_proc_template = "/api/c/compapi/v2/cc/update_proc_template/"
    list_process_instance = "/api/c/compapi/v2/cc/list_process_instance/"
    list_process_template = "/api/c/compapi/v2/cc/list_proc_template/"
    delete_service_template = "/api/c/compapi/v2/cc/delete_service_template/"
    create_service_instance = "/api/c/compapi/v2/cc/create_service_instance"
    find_module_with_relation = "/api/c/compapi/v2/cc/find_module_with_relation/"
    list_hosts_without_biz = "/api/c/compapi/v2/cc/list_hosts_without_biz/"
    add_host_to_resource = "/api/c/compapi/v2/cc/add_host_to_resource/"
    transfer_resourcehost_to_idlemodule = "/api/c/compapi/v2/cc/transfer_resourcehost_to_idlemodule/"
    transfer_host_module = "/api/c/compapi/v2/cc/transfer_host_module/"
    delete_set_template = "/api/c/compapi/v2/cc/delete_set_template/"
    list_service_category = "/api/c/compapi/v2/cc/list_service_category"

    # 真实集群名称与集群模板名映射
    set_module_dict = {
        "中控机": "controller",
        "PaaS平台": "paas",
        "用户认证平台": "user",
        "作业平台v3": "jobv3",
        "监控平台v3": "monitor",
        "管控平台": "gse",
        "配置平台": "cmdb",
        "公共组件": "public",
        "节点管理": "nodeman",
        "日志平台": "log",
        "容器管理平台": "bcs"
    }

    # 多进程单台服务器部署时无法获取进程列表. 与blueking_topo_module.tpl绑定, 新增进程可能需要更改
    # TODO: 引用qq.py完成信息来源统一
    real_module_dict = {
        'cmdb' : ["cmdb-admin","cmdb-api","cmdb-auth","cmdb-cloud","cmdb-cache","cmdb-core","cmdb-datacollection",
                                            "cmdb-event","cmdb-host","cmdb-op","cmdb-proc","cmdb-task","cmdb-topo","cmdb-web"], # cmdb 去掉 cmdb-synchronize, 并且 cmdb-operation更名为cmdb-op
        "gse" : ["gse_api","gse_task","gse_btsvr","gse_data","gse_dba","gse_alarm","gse_proc"],
        "job": ["job-config","job-gateway","job-manage","job-execute","job-crontab","job-logsvr","job-backup","job-analysis"],
        "monitor": ["influxdb-proxy","monitor","grafana","transfer",],
        "nodeman": ["nodeman-api"],
        'iam': ['bk-iam'],
        'iam_search_engine': ['bkiam-search-engine'],
        "ssm": ['bk-ssm'],
        "paas": ["paas","appengine","esb","login","apigw"],  # 社区版不存在 console
        "es7": ["elasticsearch"],
        "zk": ["zookeeper"]
    }

class Action(object):
    def __init__(self, app_code: str, app_token: str, paas_pravate_addr: str, bk_biz_id: int):
        self.app_token = app_token
        self.app_code = app_code
        self.bk_biz_id = bk_biz_id
        self.paas_pravate_addr = paas_pravate_addr

    def add_public_param(self):
        params = {}
        params["bk_app_code"]= self.app_code
        params["bk_app_secret"]= self.app_token
        params["bk_username"]= 'admin'
        return params

    def get_paas_complete_url(self, api):
        url = 'http://{}/{}'.format(self.paas_pravate_addr, api)
        return url
    
    def logging_debug_message(self, func_name,  result, params,  api=None):
        if api is None:
            logg.debug('Function -> [{}], result -> [{}], params -> [{}]'.format(func_name.__name__, result, params))
        else:
            logg.debug('Function -> [{}], api-> [{}], result -> [{}], params -> [{}]'.format(func_name.__name__, api, result, params))

    def get_set_id(self, set_module_name: str) -> str:
        params = {
            "bk_supplier_account": "0",
            "bk_biz_id": self.bk_biz_id,
            "page": {
              "start": 0,
              "limit": 50,
              "sort": "-name"
            }
        }

        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.list_set_template), data=json.dumps(params))
        result = json.loads(resp.text)
        for i in result['data']['info']:
            if i['name'] == set_module_name:
              set_module_id = i['id']
        try:
            if len(str(set_module_id)) != 0: 
                pass
        except:
            logg.error('{}没找到对应id, 请重新注册'.format(set_module_name))
            sys.exit(1)
        return set_module_id
    
    def create_set(self, set_name: str):
        try:
            set_module_name = Message.set_module_dict[set_name]
        except:
            logg.error("{} 未定义模板名称")
            sys.exit(1)

        set_module_id = self.get_set_id(set_module_name)
        params = {
            "bk_biz_id": self.bk_biz_id,
            "bk_supplier_account": "0",
            "data": {
                "bk_parent_id": self.bk_biz_id,
                "bk_set_name": set_name,
                "bk_set_desc": set_name,
                "bk_capacity": 1000,
                "description": "description",
                "set_template_id": set_module_id
            }
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.create_set), data=json.dumps(params))
        result = json.loads(resp.text)
        self.logging_debug_message(self.create_set, result, params)
        if re.search("duplicated instances exist", result['message']):
            logg.info("蓝鲸业务集群 -> [{}] 已被创建,请在页面检查是否正确".format(set_name))
        elif result["message"] == "success":
            logg.info("蓝鲸业务集群 -> [{}] 创建成功".format(set_name))
        else:
            logg.error('蓝鲸业务集群 -> [{}] 创建失败, msg -> [{}], request params -> [{}]' .format(set_name, result, params))
            sys.exit(1)

    def search_biz_inst_topo(self):
        params = {
            "bk_biz_id": self.bk_biz_id,
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.search_biz_inst_topo), data=json.dumps(params))
        result = json.loads(resp.text)
        self.logging_debug_message(self.search_biz_inst_topo, result, params)
        logg.info(result)
    
    def batch_delete_set(self,):
        params = {
            "bk_biz_id":self.bk_biz_id,
            "delete": {
            "inst_ids": [123456]
            }
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.batch_delete_set), data=json.dumps(params))
        result = json.loads(resp.text)
        self.logging_debug_message(self.batch_delete_set, result, params)
        print(result)

    def check_list_service_template(self, name):
        params = {
            "bk_biz_id":self.bk_biz_id,
            "page": {
                "start": 0,
                "limit": 200,
                "sort": "-name"
            }
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.list_service_template), data=json.dumps(params))
        result = json.loads(resp.text)
        for line in result["data"]['info']:
            if name == line['name']:
                result = True
                return result
        return False
    
    def get_service_template_id(self, name):
        params = {
            "bk_biz_id":self.bk_biz_id,
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.list_service_template), data=json.dumps(params))
        result = json.loads(resp.text)
        self.logging_debug_message(self.get_service_template_id, result, params)
        for line in result["data"]['info']:
            if name == line['name']:
                result = line['id'] 
                return result
        return False

    def delete_set_template(self):
        list_params = {
            "bk_supplier_account": "0",
            "bk_biz_id": self.bk_biz_id,
            "page": {
              "start": 0,
              "limit": 50,
              "sort": "-name"
            }
        }
        list_params.update(self.add_public_param())
        list_resp = requests.post(self.get_paas_complete_url(Message.list_set_template), data=json.dumps(list_params))
        list_result = json.loads(list_resp.text)
        self.logging_debug_message(self.delete_set_template, list_result, list_params)
        for id in list_result['data']['info']:
            delete_params = {
                    "bk_supplier_account": "0",
                    "bk_biz_id": self.bk_biz_id,
                    "set_template_ids": [id['id']]
            }
            delete_params.update(self.add_public_param())
            delete_resp = requests.post(self.get_paas_complete_url(Message.delete_set_template), data=json.dumps(delete_params))
            delete_result = json.loads(delete_resp.text)
            logg.debug('api -> [{}], delete_result -> [{}],  params -> [{}]'.format('delete_set_template', delete_result, delete_params ))
            if delete_result['message'] == 'success':
                logg.info('delete template successful! Id is -> {}'.format(id['id']))
            else:
                logg.error('delete template failed! Id is -> {}'.format(id['id']))

    def delete_service_template(self):
        params = {
            "bk_biz_id":self.bk_biz_id,
            "page": {
                "start": 0,
                "limit": 200,
                "sort": "-name"
            }
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.list_service_template), data=json.dumps(params))
        result = json.loads(resp.text)
        self.logging_debug_message(self.delete_service_template, result, params)
        for line in result["data"]['info']:
            process_id = line['id']
            drop_params = {
                "bk_biz_id":self.bk_biz_id,
                "service_template_id": int(process_id)
            }
            drop_params.update(self.add_public_param())
            resp = requests.post(self.get_paas_complete_url(Message.delete_service_template), data=json.dumps(drop_params))
            logg.debug("delete service template! result -> [{}], result -> [{}]".format(params, resp.text))
            if json.loads(resp.text)['message'] != "success":
                logg.error("delete service_template failed! params -> [{}], result -> [{}]".format(params, resp.text))
                sys.exit(1)
            else:
                logg.info("delete service_template success!, template id is -> [{}]".format(process_id))

    def update_or_create_proc_template(self=None, template_id=None, bk_func_name=None, bk_process_name=None, bk_start_param_regex=None, ip=None, port=None, protocol=None):
        create_result =  self.batch_create_proc_template(
                bk_func_name = bk_func_name, 
                template_id  = template_id,
                bk_process_name = bk_process_name, 
                bk_start_param_regex = bk_start_param_regex,
                ip = ip,
                port = port,
                protocol = protocol)
        if create_result['result'] == True:
            logg.info("proc -> [{}] create success")
            return 
        elif re.search("unique", create_result['message']):
            logg.info("proc -> [{}] 已存在,开始更新" .format(bk_process_name))
        else:
            logg.error("proc -> [{}] create failed! msg -> [{}]".format(bk_func_name, create_result['message']))
            sys.exit(1)

        params = {
            "bk_biz_id": self.bk_biz_id,
            "service_template_id" : template_id,
            "with_name": True,
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.list_process_template), data=json.dumps(params))
        result = json.loads(resp.text)
        self.logging_debug_message(self.update_or_create_proc_template, result, params)
        if result['data']['count'] != 0:
            for line in result['data']['info']:
                if line['bk_process_name'] ==  bk_process_name:
                    self.update_proc_template(
                        bk_func_name = bk_func_name, 
                        template_id  = template_id,
                        bk_process_name = bk_process_name, 
                        bk_start_param_regex = bk_start_param_regex,
                        ip = ip,
                        port = port,
                        protocol = protocol)
        sys.exit(1)
    
    def update_proc_template(self,template_id=None, bk_func_name=None, bk_process_name=None, bk_start_param_regex=None, ip=None, port=None, protocol=None):
        params = {
            "bk_biz_id": self.bk_biz_id,
            "service_template_id": template_id,
            "process_property": {
                "bk_func_name":{
                    "as_default_value": True,
                    "value": bk_func_name
                },
                "bk_process_name":{
                    "as_default_value": True,
                    "value": bk_process_name
                },
                "bk_start_param_regex":{
                    "value": bk_start_param_regex
                },
                "bind_ip": {
                    "value": ip,
                },
                "port": {
                    "value": port,
                    "as_default_value": True 
                },
                "protocol": {
                  "value": str(protocol),
                  "as_default_value": True
                },
            }
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.update_proc_template), data=json.dumps(params))
        result = json.loads(resp.text)
        self.logging_debug_message(self.update_proc_template, result, params)
        logg.error(result)
        sys.exit(1)

    def get_category_id(self):
        params = {
                  "bk_biz_id": self.bk_biz_id,
                }
        params.update(self.add_public_param())
        module_resp = requests.post(self.get_paas_complete_url(Message.list_service_category), data=json.dumps(params))
        module_result = json.loads(module_resp.text)
        ids = []
        for i in module_result['data']['info']:
            if i['name'] == 'Default' and i ['bk_parent_id'] != 0:
                ids.append(i['id'])
        if len(ids) > 1:
            logg.error('服务分类id个数超过1, ids -> [{}], api -> [{}], result-> [{}], params -> [{}]' .format(
                ids, Message.list_service_category, module_result, params 
            ))
        else:
            logg.debug('服务分类Default id -> %s' % ids[0])
            return ids[0] 

    def create_service_template (self, name):
        params = {
            "bk_biz_id": self.bk_biz_id, 
            "service_category_id": self.get_category_id(), 
            "name": name,
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.CREATE_SERVICE_TEMPLATE), data=json.dumps(params))
        result = json.loads(resp.text)
        self.logging_debug_message(self.create_service_template, result, params)
        if result["code"] == 0:
            logg.info('服务模板 -> [{}] 创建成功'.format(name))
            return "create", result["data"]['id']
        elif re.search("duplicated", result["message"]) :
            service_id = self.get_service_template_id(name)
            logg.info('服务模板 -> [{}] 已存在, 开始更新或创建进程模板'.format(name))
            return "update", service_id
        else:
            logg.error('服务模板 -> [{}] 创建失败 -> [{}]'.format(name, result['message']))
            sys.exit(1)
    
    def create_blueking_service_template(self, topo_file: str):
        """
        params: top_file 是以tab为分割符的7行格式文件
        """
        with open(topo_file) as e:
            for line in e:
                line = line.strip("\n")
                if not re.search("^[a-z]", line):
                    continue
                service = line.split("\t")
                if len(service) == 7:
                    action, id = self.create_service_template(service[0])
                    if service[6] == "TCP":
                        proc = "1"
                    elif service[6] == "UDP":
                        proc = "2"
                    else:
                        proc = None

                    if service[4] == '127.0.0.1':
                        ip = "1"
                    elif service[4] == '0.0.0.0':
                        ip = "2"
                    else:
                        ip = '3'
                else:
                    logg.error("tpl file -> [{}] 中该行 -> [{}] 列数不为7, service-> [{}], len={}" .format(topo_file, line, service, len(service)))
                    raise Exception("请确认tpl文件是否正确")
                    
                #  controller_ip 不监控
                is_enable = True if  service[2] != "controller_ip" else False 
                if action == "create":
                    result = self.batch_create_proc_template(
                        bk_func_name = service[1],
                        template_id =id,
                        bk_process_name = service[2],
                        bk_start_param_regex = service[3], 
                        ip = ip,
                        port = service[5],
                        protocol = proc,
                        is_enable = is_enable
                    )
                    if result['result'] is True:
                        logg.debug("Create proc template -> [%s] result success" % service[2] )
                    else:
                        logg.debug("Create proc template -> [%s] result failed, 如果该进程不需要被监控则忽略报错" % service[2] )
                elif action == 'update':
                    self.update_or_create_proc_template(
                        bk_func_name = service[1],
                        template_id =id,
                        bk_process_name = service[2],
                        bk_start_param_regex = service[3], 
                        ip = ip,
                        port = service[5],
                        protocol = proc,
                    )

    def batch_create_proc_template(self=None, template_id=None, bk_func_name=None, bk_process_name=None, bk_start_param_regex=None, ip=None, port=None, protocol=None, is_enable=True):
        params = {
            "bk_biz_id": int(self.bk_biz_id),
            "service_template_id": template_id,
            "processes":[
                    {
                        "spec":{
                        "bk_func_name":{
                            "as_default_value": True,
                            "value": bk_func_name
                        },
                        "bk_process_name":{
                            "as_default_value": True,
                            "value": bk_process_name
                        },
                        "bk_start_param_regex":{
                            "as_default_value": True,
                            "value": bk_start_param_regex
                        },
                        "bind_info":{
                            "value":[
                                {
                                    "enable":{
                                        "value": is_enable,
                                        "as_default_value":  True
                                    },
                                    "ip":{
                                        "value":ip,
                                        "as_default_value": True
                                    },
                                    "port":{
                                        "value": port,
                                        "as_default_value": True
                                    },
                                    "protocol":{
                                        "value": protocol,
                                        "as_default_value": True
                                    }
                                }
                            ],
                            "as_default_value":True
                        }
                    }
                }
            ]
        }
        params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.batch_create_proc_template), data=json.dumps(params))
        result = json.loads(resp.text)
        logg.debug("Func -> [{}], result -> [{}], params -> [{}]".format("batch_create_proc_template", json.loads(resp.text), params))
        return result

    def transfer_resourcehost_to_idlemodule(self, ip):
        # 新增主机到资源池
        select_count = 1
        add_host_to_resource_p  = {
                "bk_supplier_account": "0",
                "host_info": {
                    "0": {
                        "bk_host_innerip": ip,
                        "bk_cloud_id": 0,
                        "import_from": "3"
                    }
                }
            }
        add_host_to_resource_p.update(self.add_public_param())
        add_resp = requests.post(self.get_paas_complete_url(Message.add_host_to_resource), data=json.dumps(add_host_to_resource_p))
        add_result = json.loads(add_resp.text)
        self.logging_debug_message(self.transfer_resourcehost_to_idlemodule, add_result, add_host_to_resource_p, Message.add_host_to_resource)
        if add_result['message'] == "success":
            logg.debug("新增主机 ->[{}] 到资源池".format(ip))
            # 查询主机host id
            list_hosts_without_biz_p = {
                "bk_supplier_account": "0",
                "page": {
                    "start": 0,
                    "limit": 500,
                },
                "fields": [
                    "bk_host_id",
                    "bk_cloud_id",
                    "bk_host_innerip",
                ],
                "host_property_filter": {
                    "condition": "AND",
                    "rules": [
                      {
                          "field": "bk_host_innerip",
                          "operator": "begins_with",
                          "value": ip,
                      }]
                    }
            }
            list_hosts_without_biz_p.update(self.add_public_param())
            while select_count < 4:
                try:
                    list_hosts_resp = requests.post(self.get_paas_complete_url(Message.list_hosts_without_biz), data=json.dumps(list_hosts_without_biz_p))
                    list_hosts_resp = json.loads(list_hosts_resp.text)
                    self.logging_debug_message(self.transfer_resourcehost_to_idlemodule, list_hosts_resp, list_hosts_without_biz_p, Message.list_hosts_without_biz)
                    if list_hosts_resp['message'] == 'success' and list_hosts_resp['data']['info'][0]['bk_host_innerip'] == ip:
                        host_id = list_hosts_resp['data']['info'][0]['bk_host_id']
                    else:
                        logg.error("主机 -> [{}] 通过api -> [{}], 查询到的结果不符合预期, params -> [{}], result -> [{}]". format(ip, 
                                                                                    Message.list_hosts_without_biz, list_hosts_without_biz_p, list_hosts_resp))
                        sys.exit(1)
                    break
                except Exception as e:
                    select_count += 1
                    time.sleep(1)
                    pass
            else:
                logg.error("主机 -> [{}] 已执行注册动作但是并未查询到HOST ID. 耗时 -> [{}] 秒".format(ip, select_count))
                sys.exit(1)
            logg.debug("主机 -> [{}] host id -> [{}], 共查询了 -> [{}] 次".format(ip, host_id, select_count))
        else:
            logg.error('新增主机-> [{}] 到资源池失败 msg -> [{}]'.format(ip, add_result))
            sys.exit(1)

        # 上交主机到业务空闲机
        transfer_resourcehost_to_idlemodule_p = {
                "bk_supplier_account": "0",
                "bk_biz_id": self.bk_biz_id,
                "bk_host_id": [
                    host_id
                ] 
            }
        transfer_resourcehost_to_idlemodule_p.update(self.add_public_param())
        transfer_resp = requests.post(self.get_paas_complete_url(Message.transfer_resourcehost_to_idlemodule), data=json.dumps(transfer_resourcehost_to_idlemodule_p))
        transfer_result = json.loads(transfer_resp.text)
        self.logging_debug_message(self.transfer_resourcehost_to_idlemodule, transfer_result, transfer_resourcehost_to_idlemodule_p, Message.transfer_resourcehost_to_idlemodule)
        if transfer_result['message'] == "success":
            logg.debug("主机 -> [{}] 转移到蓝鲸业务空闲机" .format(ip))
            return host_id
        else:
            logg.error("主机 -> [{}] 转移到业务空闲机失败, msg -> [{}]".format(ip, transfer_result))
            sys.exit(1)
    
    def blueking_set_host_check(self, host_id: int) -> bool:
        """
        查询指定的主机id是否在蓝鲸业务中
        return bool
        """
        list_biz_hosts_p = {
            "bk_biz_id": self.bk_biz_id, 
            "bk_supplier_account": "0", 
            "fields": [
                "bk_host_id", 
                "bk_cloud_id", 
                "bk_host_innerip", 
                "bk_os_type", 
                "bk_mac"
            ], 
            "page": {
                "start": 0, 
                "limit": 500, 
                "sort": "bk_host_id"
            }
        }
        list_biz_hosts_p.update(self.add_public_param())
        list_biz_host_result = requests.post(self.get_paas_complete_url(Message.list_biz_hosts), data=json.dumps(list_biz_hosts_p))
        self.logging_debug_message(self.blueking_set_host_check, json.loads(list_biz_host_result.text), list_biz_hosts_p, Message.list_biz_hosts)
        hosts = [ ip['bk_host_id'] for ip in json.loads(list_biz_host_result.text)['data']['info'] ]
        if host_id in hosts:
            logg.debug('主机id -> [{}] 已存在于蓝鲸业务, 蓝鲸业务HOST-ID: -> [{}]'.format(host_id, hosts))
            return True 
        else:
            logg.debug("主机id -> [{}] 不存在于蓝鲸业务,但存在于主机资源池，请上交主机到资源池".format(host_id))
            return False 

    def create_service_instance(self, service_template_name=None,ip=None, module_name=None):
        # 查询主机host id
        list_hosts_without_biz_p = {
            "bk_supplier_account": "0",
            "page": {
                "start": 0,
                "limit": 500,
            },
            "fields": [
                "bk_host_id",
                "bk_cloud_id",
                "bk_host_innerip",
            ],
            "host_property_filter": {
                "condition": "AND",
                "rules": [
                  {
                      "field": "bk_host_innerip",
                      "operator": "begins_with",
                      "value": ip,
                  }]
                }
        }
        list_hosts_without_biz_p.update(self.add_public_param())
        list_hosts_resp = requests.post(self.get_paas_complete_url(Message.list_hosts_without_biz), data=json.dumps(list_hosts_without_biz_p))
        list_hosts_resp = json.loads(list_hosts_resp.text)
        self.logging_debug_message(self.create_service_instance, list_hosts_resp, list_hosts_without_biz_p, Message.list_hosts_without_biz)
        if list_hosts_resp['message'] == 'success':
            try:
                if list_hosts_resp['data']['info'][0]['bk_host_innerip'] == ip:
                    host_id = list_hosts_resp['data']['info'][0]['bk_host_id']
            except Exception as e:
                logg.debug("未在资源池找到 -> [{}] 对应的主机id, result -> [{}],  requests -> [{}], Exception -> [{}]".format(ip, list_hosts_resp, list_hosts_without_biz_p, e))
                host_id = self.transfer_resourcehost_to_idlemodule(ip)
        if not self.blueking_set_host_check(host_id):
            host_id = self.transfer_resourcehost_to_idlemodule(ip)
        logg.debug("{} host id is {}".format(ip, host_id))
        if not self.blueking_set_host_check(host_id):
            transfer_resourcehost_to_idlemodule_p = {
                    "bk_supplier_account": "0",
                    "bk_biz_id": self.bk_biz_id,
                    "bk_host_id": [
                        host_id
                    ] 
                }
            transfer_resourcehost_to_idlemodule_p.update(self.add_public_param())
            transfer_resp = requests.post(self.get_paas_complete_url(Message.transfer_resourcehost_to_idlemodule), data=json.dumps(transfer_resourcehost_to_idlemodule_p))
            transfer_result = json.loads(transfer_resp.text)
            self.logging_debug_message(self.create_service_instance, transfer_result, transfer_resourcehost_to_idlemodule_p, Message.transfer_resourcehost_to_idlemodule)
            if transfer_result['message'] == "success":
                logg.debug("主机 -> [{}] 转移到蓝鲸业务空闲机" .format(ip))
            else:
                logg.error("主机 -> [{}] 转移到业务空闲机失败, msg -> [{}]".format(ip, transfer_result))
                sys.exit(1)

        #  根据模板名称获取模板id 
        list_params = {
            "bk_biz_id":self.bk_biz_id,
            "page": {
                "start": 0,
                "limit": 200,
                "sort": "-name"
            }
        }
        list_params.update(self.add_public_param())
        resp = requests.post(self.get_paas_complete_url(Message.list_service_template), data=json.dumps(list_params))
        result = json.loads(resp.text)
        self.logging_debug_message(self.create_service_instance, result, list_params, Message.list_service_template)
        try:
            for template in result['data']['info']:
                if template['name'] == service_template_name:
                    service_template_id = template['id']
                    logg.debug("%s template id is %s", service_template_name, service_template_id)
                    break
            else:
                logg.error("Service template %s not found, service_template_name -> [%s], params -> [%s]" %(service_template_name, service_template_name, list_params))
                sys.exit(1)
        except Exception as e :
            logg.error("Service template %s not found, service_template_name -> [%s], params -> [%s], error -> [%s]" %(service_template_name, service_template_name, list_params, e))
            sys.exit(1)
        
        # 根据模块名获取模块id
        get_module_id_params = {
                "bk_biz_id": self.bk_biz_id,
                "bk_set_ids":[ i for i in range(1,201) ],

                "fields":["bk_module_id", "bk_module_name"],
                "page": {
                    "start": 0,
                    "limit": 500
                }
            }
        get_module_id_params.update(self.add_public_param())
        module_resp = requests.post(self.get_paas_complete_url(Message.find_module_with_relation), data=json.dumps(get_module_id_params))
        module_result = json.loads(module_resp.text)
        self.logging_debug_message(self.create_service_instance, module_result, get_module_id_params, Message.find_module_with_relation)
        
        
        module_name_with_id = { m['bk_module_name']: m['bk_module_id'] for m in module_result['data']['info'] }
        module_names = [ y['bk_module_name'] for y in module_result['data']['info'] ]
        logg.debug('module name is: %s and  list is : %s, ids : [%s] ' % (module_name, module_names, module_name_with_id))
        if module_name not in module_names:
            logg.error('module ->[{}] is not in module list: {}'.format(module_name, module_names))
            sys.exit(1)
        module_id = module_name_with_id[module_name]
        logg.debug('{} id is {}'.format(module_name, module_id))

        transfer_host_module_p = {
                "bk_supplier_account": "0",
                "bk_biz_id": self.bk_biz_id,
                "bk_host_id": [
                    host_id
                ],
                "bk_module_id": [
                    module_id
                ],
                "is_increment": True
        }
        transfer_host_module_p.update(self.add_public_param())
        transfer_resp = requests.post(self.get_paas_complete_url(Message.transfer_host_module), data=json.dumps(transfer_host_module_p))
        transfer_result = json.loads(transfer_resp.text)
        self.logging_debug_message(self.create_service_instance, transfer_result, transfer_host_module_p, Message.transfer_host_module)
        try:
            if transfer_result["message"] == "success":
                logg.info("Host -> [{}]  registered module -> [{}] success".format(ip, module_name))
            else:
                logg.error("Module -> [{}] register failed, msg -> [{}]".format(module_name, transfer_result))
                sys.exit(1)
        except Exception as e:
                logg.error("Module -> [{}] register failed. msg -> [{}]".format(module_name, e))
                sys.exit(1)
        
    def batch_create_service_instance(self, filename):
        installed_modules , ip = Parse.parse_file(filename) 
        try:
            installed_modules , ip = Parse.parse_file(filename) 
        except Exception as e: 
            logg.error('Parse installed module file -> [{}] failed, msg -> [{}]'.format(filename, e))
            sys.exit(1)
        for service in installed_modules:
            self.create_service_instance(
                service_template_name = service,
                ip = ip,
                module_name = service,
            )

class Parse():
    """
    解析pcmd执行返回的未过滤.installed_module文件
    """
    @classmethod
    def parse_file(cls, filename):
        installed_modules = []
        with open(filename, 'r') as f:
            for line in f:
                # 过滤空行
                if len(line.strip()) == 0:
                    continue
                # 过滤掉注释及标注行
                if re.search('^(#)', line.strip()):
                    continue
                # 匹配[开头行
                if re.search('^\[', line.strip()):
                    # 匹配ip 地址
                    if re.search('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', line.strip()) and re.search('SUCCESS', line.strip()):
                        lan_ip = re.search('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', line.strip()).group()
                        continue
                # 排除掉Python
                if re.search('python|nfs|yum|notty|There|Stderr|stderr|lesscode', line.strip()):
                    continue
                if re.search("monitorv3", line):
                    line = line.replace("monitorv3_" ,"").strip()
                elif re.search("^gse$", line):
                    line = Message.real_module_dict['gse']
                elif re.search("^cmdb$", line):
                    line = Message.real_module_dict['cmdb']
                else:
                    try:
                        line = Message.real_module_dict[line.strip()]
                    except Exception as e:
                        line = line.strip()
                
                if type(line) == list:
                    for i in line:
                        installed_modules.append(i)
                else:
                    installed_modules.append(line)
        return installed_modules, lan_ip
                
if __name__ == '__main__':
    p =  argparse.ArgumentParser()
    p.add_argument('-c', dest="app_code",  help="app code")
    p.add_argument('-t', dest="app_token",  help="app token")
    p.add_argument('-p', default="paas.service.consul:80", dest="url", help="paas private url")
    p.add_argument('-b', dest="bk_biz_id", default=2, help="蓝鲸业务ID")
    p.add_argument('-i', dest="ip", help="实例的ip地址")
    p.add_argument('-m', dest="module_name", help="模块名")
    p.add_argument('-f', dest="batch_create_file",  help=".installed_module file PATH")
    p.add_argument('--create-service', action="store_true", dest="create_service",  help="app code")
    p.add_argument('--create-set', action="store_true", dest="create_set",  help="app code")
    p.add_argument('--create-proc-instance', action="store_true", dest="create_proc_instance", help="create proc instance")
    p.add_argument('--tpl', dest="service_tpl", default="/data/install/bin/default/blueking_service_module.tpl", help="app code")
    p.add_argument('--delete', dest="delete_service_template", action="store_true", help="删除蓝鲸业务所有的服务模板"  )

    args = p.parse_args()
    log_fmt = "%(asctime)s %(lineno)-4s %(levelname)-6s %(message)s"
    date_fmt = "%Y-%m-%d %H:%M:%S"
    formatter = logging.Formatter(log_fmt)
    logging.getLogger("requests").propagate = False

    logg = logging.Logger(name='blueking')
    fh = logging.FileHandler("/tmp/create_blueking_set.log")
    fh.setLevel('DEBUG')
    fh.setFormatter(formatter)
    ch = logging.StreamHandler()
    ch.setLevel('INFO')
    ch.setFormatter(formatter)
    logg.addHandler(ch)
    logg.addHandler(fh)

    action = Action(args.app_code, args.app_token, args.url, args.bk_biz_id)
    p_list = [ args.create_service, args.create_set, args.create_proc_instance, args.delete_service_template ]
    real_list = [ i for i in p_list if i ]

    if len(real_list) != 1:
        logg.error("--create 参数个数为%s ", len(real_list))
        sys.exit(1)
    if args.delete_service_template:
        action.delete_service_template()  # 删掉所有已存在服务模板
        action.delete_set_template()  # 删掉所有已存在集群模板
    if args.create_service:
        action.create_blueking_service_template(args.service_tpl)
    if args.create_set:
        for set_name in Message.set_module_dict.keys():
            action.create_set(set_name) 
    if args.create_proc_instance:
        action.batch_create_service_instance(args.batch_create_file)