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

# Update Elasticsearch node list
cp /etc/elasticsearch/elasticsearch.yml.template /etc/elasticsearch/elasticsearch.yml
echo "discovery.zen.ping.unicast.hosts: [${ES_NODES}]" >> /etc/elasticsearch/elasticsearch.yml

