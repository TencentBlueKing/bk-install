service_template	bk_func_name	bk_process_name	bk_start_param_regex	bind_ip	port	protocol
bk-iam	iam	bk-iam	bkiam_config.yaml		5001	TCP
bk-ssm	ssm	ssm	bkssm_config.yaml		5000	TCP
						
appengine	uwsgi	open_paas-appengine	uwsgi-open_paas-appengine.ini		8000	TCP
paas	uwsgi	open_paas-paas	uwsgi-open_paas-paas.ini		8001	TCP
esb	uwsgi	open_paas-esb	uwsgi-open_paas-esb.ini		8002	TCP
login	uwsgi	open_paas-login	uwsgi-open_paas-login.ini		8003	TCP
apigw	uwsgi	open_paas-apigw	uwsgi-open_paas-apigw.ini		8005	TCP
appo	paas_agent	paas_agent			4245	TCP
appt	paas_agent	paas_agent			4245	TCP
						
job-config	java	job-config	job-config.jar	0.0.0.0	10500	TCP
job-crontab	java	job-crontab	job-crontab.jar	0.0.0.0	10501	TCP
job-execute	java	job-execute	job-execute.jar	0.0.0.0	10502	TCP
job-gateway	java	job-gateway	job-gateway.jar	0.0.0.0	10503	TCP
job-logsvr	java	job-logsvr	job-logsvr.jar	0.0.0.0	10504	TCP
job-manage	java	job-manage	job-manage.jar	0.0.0.0	10505	TCP
job-backup	java	job-backup	job-backup.jar	0.0.0.0	10507	TCP
job-analysis	java	job-analysis	job-analysis.jar	0.0.0.0	10508	TCP
						
gse_api	gse_api	gse_api			50002	TCP
gse_alarm	gse_alarm	gse_alarm		0.0.0.0		TCP
gse_btsvr	gse_btsvr	gse_btsvr		0.0.0.0	58930	TCP
gse_data	gse_data	gse_data		0.0.0.0	58625	TCP
gse_dba	gse_dba	gse_dba			58817	TCP
gse_proc	gse_procmgr	gse_procmgr			52030	TCP
gse_task	gse_task	gse_task			48669	TCP
gse_syncdata	gse_syncdata	gse_syncdata			52050	TCP
						
cmdb-admin	cmdb_adminserver	cmdb_adminserver			9000	TCP
cmdb-api	cmdb_apiserver	cmdb_apiserver			9001	TCP
cmdb-auth	cmdb_authserver	cmdb_authserver			9002	TCP
cmdb-cloud	cmdb_cloudserver	cmdb_cloudserver			9003	TCP
cmdb-core	cmdb_coreservice	cmdb_coreservice			9004	TCP
cmdb-datacollection	cmdb_datacollection	cmdb_datacollection			9005	TCP
cmdb-event	cmdb_eventserver	cmdb_eventserver			9006	TCP
cmdb-host	cmdb_hostserver	cmdb_hostserver			9007	TCP
cmdb-op	cmdb_operationserver	cmdb_operationserver			9008	TCP
cmdb-proc	cmdb_procserver	cmdb_procserver			9009	TCP
cmdb-synchronize	cmdb_synchronizeserver	cmdb_synchronizeserver			9010	TCP
cmdb-task	cmdb_taskserver	cmdb_taskserver			9011	TCP
cmdb-topo	cmdb_toposerver	cmdb_toposerver			9012	TCP
cmdb-web	cmdb_webserver	cmdb_webserver			9013	TCP
cmdb-cache	cmdb_cacheservice	cmdb_cacheservice			9014	TCP
						
						
monitor	python	bk-monitor	gunicorn_config.py		10204	TCP
transfer	transfer	bk-transfer			10202	TCP
influxdb-proxy	influxdb-proxy	bk-influxdb-proxy			10203	TCP
grafana	grafana-server	bk-grafana	logs/bkmonitorv3/	0.0.0.0	3000	TCP
unify-query	unify-query	bk-unify-query			10206	TCP
						
fta-api	python	fta-api	apiserver		13031	TCP
						
nodeman-api	python	nodeman-api	bknodeman-nodeman/bin/gunicorn		10300	TCP
						
bklog-api	python	bklog-api	bklog-api/bin/gunicorn -c gunicorn_config		10400	TCP
bklog-grafana	grafana-server	bk-log-grafana	logs/bklog/		10401	TCP
						
						
beanstalk	beanstalkd	beanstalkd	beanstalkd	0.0.0.0	11300	TCP
consul	consul	consul	-config-dir=/etc/consul.d	127.0.0.1	8500	TCP
elasticsearch	java	elasticsearch	/usr/share/elasticsearch/jdk/bin/java		9200	TCP
influxdb	influxd	influxdb			8086	TCP
kafka	java	kafka	/etc/kafka/server.properties		9092	TCP
mongodb	mongod	mongod	/etc/mongod.conf	127.0.0.1	27017	TCP
mysql	mysqld	mysql			3306	TCP
nginx	nginx	nginx	/usr/local/openresty/nginx/sbin/nginx	0.0.0.0	80	TCP
rabbitmq	beam.smp	rabbitmq	beam.smp	0.0.0.0	5672	TCP
redis	redis-server	redis-server			6379	TCP
zookeeper	java	zookeeper	/etc/zookeeper		2181	TCP
consul-template	consul-template	consul-template	/etc/consul-template/conf.d	0.0.0.0		TCP
						
						
controller_ip	controller_ip					
usermgr	python	usermgr	usermgr-api/bin/gunicorn	0.0.0.0	8009	TCP
license	license_server	license	license.json	0.0.0.0	8443	TCP
						
bcs	bcs	bcs				TCP