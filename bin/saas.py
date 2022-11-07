#!/opt/py36/bin/python
# -*- coding: utf8

import os
import re 
import sys
import time
import logging
import json

import argparse
import requests
import pymysql

import urllib3
urllib3.disable_warnings()

class AppManager(object):

    def __init__(self, paas_domain, bk_paas_app_secret):
        self.paas_domain = paas_domain
        self.bk_paas_app_secret = bk_paas_app_secret
        self.bk_paas_app_code =  "bk_paas"

    def common_headers(self):
        headers = {
            "X-APP-CODE": self.bk_paas_app_code,
            "X-APP-TOKEN" : self.bk_paas_app_secret
        }
        return headers

    def upload_pkg(self, file_path, upload_url):

        files = { 'saas_file': open(file_path, 'rb') }

        logg.info("uploading file {}, url:{}, headers: {} ...".format(file_path, upload_url, self.common_headers()))
        logg.info(upload_url)
        resp = requests.post(upload_url, files=files, headers=self.common_headers())
        logg.info(resp.content)

        if resp.status_code != 200:
            logg.error("upload faild:{}".format(resp.content))
            sys.exit(1)

        if "danger"  in resp.text:
            logg.info("upload package failed!: {}".format(resp.text.encode('utf-8')))
            sys.exit(1)

    def deploy(self, url, env):

        env_data = { "mode": env }

        logg.info("start deploy {}".format(args.app_code))
        resp = requests.post(url=url,
                data=env_data,
                headers=self.common_headers()
                )
        if resp.status_code != 200 or json.loads(resp.text)['result'] != True:
            logg.error(u"request deploy api failed: {}".format(json.loads(resp.text)['msg']))
            sys.exit(1)

        logg.info(u"resposne: {}".format(resp.json()))
        deploy_result = resp.json()
        if deploy_result['result'] is False:
            logg.info(u"{}".format(deploy_result["msg"]))
            sys.exit(1)

        return deploy_result["event_id"], deploy_result["app_code"]


    def check_result(self, url, app_code, event_id, timeout):
        for i in range(timeout):
            time.sleep(2)
            logg.info("check deploy result. retry {}".format(i))
            resp = requests.get("{}{}/?event_id={}".format(url, app_code, event_id), headers=self.common_headers())
            if resp.json()["result"] == True:
                if resp.json()["data"]["status"] == 2:
                    logg.debug("check result: {}".format(resp.json()))
                elif resp.json()["data"]["status"] == 1:
                    logg.info("{} have been deployed successfully".format(app_code))
                    return resp.json
                else:
                    logg.error("\x1b[31;40mdeploy failed: timeout\x1b[0m")
                    sys.exit(1)


class SimpleDB(object):
    def __init__(self, **kwargs):
        self.dbc = pymysql.connect(**kwargs)

    def close(self):
        self.dbc.close()

    def execute(self, sql):
        cursor = self.dbc.cursor()
        cursor.execute(sql)

        rec = cursor.fetchone()
        if rec:
            return rec[0]
        else:
            return None

    def __del__(self):
        self.close()

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('-e', action='store', dest='deploy_env', help='which env to deploy, i.e: appt or appo')
    p.add_argument('-n', action='store', dest='app_code', help='app code')
    p.add_argument('-k', action='store', dest='pkg_path', help='saas package path')
    p.add_argument('-f', action='store', dest='env_file', help='parse specified file to load environ')
    p.add_argument('-d', action='store_true', dest='debug_enable', help='debug mode')
    args = p.parse_args()

    saas_env = {
            'appt': 'test',
            'appo': 'prod'
        }

    if args.debug_enable:
        log_level = logging.DEBUG
    else:
        log_level = logging.INFO


    app_code = args.app_code

    # 日志配置
    log_fmt = "%(asctime)s %(lineno)-4s %(levelname)-6s %(message)s"
    date_fmt = "%Y-%m-%d %H:%M:%S"

    formatter = logging.Formatter(log_fmt)
    logging.basicConfig(format=log_fmt, datefmt=date_fmt, level=log_level)

    fh = logging.FileHandler("/tmp/deploy_saas.log")
    fh.setFormatter(formatter)

    logg = logging.getLogger()
    logg.addHandler(fh)

    # 解析环境变量文件，并导入
    paas_env_file = args.env_file
    if not os.path.isfile(paas_env_file):
        logg.error('\x1b[31;40m%s 文件不存在\x1b[0m' % paas_env_file)
        sys.exit(1)

    with open(paas_env_file, 'r') as e:
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
            # 去除 '\'
            line = line.replace('\\', '')

            # 导入当前环境变量
            env_key, env_value = re.split('=', line, maxsplit=1)
            os.environ[env_key] = env_value

    # DB 信息, 从环境变量中获取
    db_config = {
            "host": os.environ.get('BK_PAAS_MYSQL_HOST','mysql-paas.service.consul'),
            "user": os.environ.get("BK_PAAS_MYSQL_USER",'paas'),
            "passwd": os.environ.get("BK_PAAS_MYSQL_PASSWORD"),
            "port": int(os.environ.get("BK_PAAS_MYSQL_PORT", 3306)),
            "db": 'open_paas'
    }

    x = SimpleDB(**db_config)

    # Paas 登陆信息, 从环境变量中获取
    HTTP_SCHEMA = "http"
    paas_domain = '{}'.format(os.environ.get('BK_PAAS_PRIVATE_ADDR'))
    username = os.environ.get('BK_PAAS_ADMIN_USERNAME')
    password = os.environ.get('BK_PAAS_ADMIN_PASSWORD')
    bk_paas_app_secret = os.environ.get('BK_PAAS_APP_SECRET')

    checknew_sql = "select id from open_paas.paas_saas_app where code='{}'".format(args.app_code)
    if not x.execute(checknew_sql):
        # 首次上传, 设置 app_code 为0
        app_code = "0"

    # 各步骤 url 设置
    check_app_url = "{}://{}/app/list/".format(HTTP_SCHEMA, paas_domain)

    upload_url = "{}://{}/saas/upload0/{}/".format(HTTP_SCHEMA, paas_domain, app_code)

    # main progress
    appmgr = AppManager(paas_domain, bk_paas_app_secret)
    appmgr.upload_pkg(args.pkg_path, upload_url)

    event_id_SQL = """
        SELECT a.id FROM paas_saas_app_version a, paas_saas_app b, paas_saas_upload_file c 
        WHERE code='{}' and a.saas_app_id = b.id and a.upload_file_id = c.id
        ORDER BY c.id desc limit 1
    """.format(args.app_code)

    x = SimpleDB(**db_config)
    saas_version_id = x.execute(event_id_SQL)
    deploy_url = "{}://{}/saas/release/online0/{}/".format(HTTP_SCHEMA, paas_domain, saas_version_id)

    logg.info("query saas_version_id: {}".format(saas_version_id))

    logg.info("start deploy app:{} url: {}".format(args.app_code, deploy_url))
    event_id, app_code = appmgr.deploy(deploy_url, saas_env[args.deploy_env])

    check_event_url = "{}://{}/release/get_app_poll_task0/".format(HTTP_SCHEMA, paas_domain)
    logg.info("checking deploy result...")
    appmgr.check_result(check_event_url, app_code, event_id, 600)