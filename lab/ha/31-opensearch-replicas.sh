#!/usr/bin/env bash
# Artifact Keeper legt seine Indizes (artifacts, repositories) mit number_of_replicas=0 an
# (Single-Node-Default). Im 3-Knoten-Cluster geht der Index dann beim Ausfall EINES Knotens auf RED.
# Fix: Replikas fuer bestehende Indizes setzen + Template fuer kuenftig angelegte Indizes.
OS=${1:-http://192.168.56.11:9200}
curl -s -X PUT "$OS/_index_template/artifact-keeper-replicas" -H 'Content-Type: application/json' -d '{
  "index_patterns": ["artifacts*", "repositories*"],
  "priority": 100,
  "template": { "settings": { "index.number_of_replicas": 1 } }
}'; echo
curl -s -X PUT "$OS/artifacts,repositories/_settings" -H 'Content-Type: application/json' \
  -d '{"index": {"number_of_replicas": 1}}'; echo
sleep 5
curl -s "$OS/_cat/indices/artifacts,repositories?v&h=health,index,pri,rep,docs.count"
curl -s "$OS/_cat/shards/artifacts,repositories?v&h=index,shard,prirep,state,node"
