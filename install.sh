#!/bin/bash
set -o errexit
set -o nounset

# Collect running nodes
eval $(szradm queryenv --format=json list-roles farm-role-id=${SCALR_FARM_ROLE_ID} | python -c '
import sys, json, pipes, os
data = json.load(sys.stdin)
ips = []
for host in (data["roles"][0]["hosts"]):
    ips.append(host["internal-ip"] + ":9300")
if len(ips) == 0:
    print "export ES_NODES="
else:
    print "export ES_NODES='"'"'\"%s\"'"'"'" % '"'"'", "'"'"'.join(ips)
')

# Install Oracle Java 8
apt-get update
apt-get install -y python-software-properties
add-apt-repository -y ppa:webupd8team/java
apt-get update
echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections
apt-get install -y oracle-java8-installer

# Install Elasticsearch
cd /opt
wget -q "https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.7.1.deb"
dpkg -i elasticsearch-1.7.1.deb
echo "discovery.zen.ping.multicast.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
echo "network.publish_host: ${SCALR_INTERNAL_IP}" >> /etc/elasticsearch/elasticsearch.yml
cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.template
echo "discovery.zen.ping.unicast.hosts: [${ES_NODES}]" >> /etc/elasticsearch/elasticsearch.yml
/usr/share/elasticsearch/bin/plugin -install mobz/elasticsearch-head
service elasticsearch start

# Install Kibana
curl -L https://download.elastic.co/kibana/kibana/kibana-4.1.1-linux-x64.tar.gz | tar xzf -
sed -i 's/0.0.0.0/127.0.0.1/g' /opt/kibana-4.1.1-linux-x64/config/kibana.yml
/opt/kibana-4.1.1-linux-x64/bin/kibana &
echo "/opt/kibana-4.1.1-linux-x64/bin/kibana &" >> /etc/rc.local

# Install Nginx
apt-get install -y nginx
unlink /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/kibana <<EOL
server {
  listen 80 default_server;
  root /opt/kibana-4.1.1-linux-x64;
  index index.html index.htm;
  server_name localhost;
  location / {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;  
    proxy_pass http://127.0.0.1:5601;
  }
}
EOL
ln -s /etc/nginx/sites-available/kibana /etc/nginx/sites-enabled/kibana
apt-get install -y apache2-utils
htpasswd -bc /etc/nginx/.htpasswd ${USERNAME} ${PASSWORD}

service nginx restart

# Install Fluentd
wget "http://packages.treasuredata.com.s3.amazonaws.com/2/ubuntu/trusty/pool/contrib/t/td-agent/td-agent_2.2.1-0_amd64.deb"
dpkg -i td-agent_2.2.1-0_amd64.deb
apt-get install -y make libcurl4-gnutls-dev
/opt/td-agent/embedded/bin/fluent-gem install fluent-plugin-elasticsearch
/opt/td-agent/embedded/bin/fluent-gem install fluent-plugin-record-reformer
cat > /etc/td-agent/td-agent.conf <<EOL
<source>
  type http
  port 8888
</source>
<source>
 type syslog
 port 5140
 tag  system
</source>
<match **>
 type elasticsearch
 host localhost
 port 9200
 logstash_format true
 flush_interval 5s
</match>
EOL
/etc/init.d/td-agent restart

