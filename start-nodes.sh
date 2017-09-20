#!/bin/bash
#set -x
localIP=$(ifconfig enp0s3 | grep -oP "inet addr:[0-9.]{7,15} " | cut -f 2 -d :)

# Start manager node
startNodeCMD=$(docker swarm init --advertise-addr $localIP | grep 'docker swarm join \\' -A2 | sed  's/\\//g' | tr '\n' ' ')

nodes="wnode@worker1 wnode@worker2"

restartNetwork="sudo systemctl restart network-manager.service && sudo systemctl restart docker"

# Start worker nodes
for node in $nodes
do
    echo "Restarting network on $node"
    ssh -t $node "$restartNetwork"
    echo "Connecting node: $node"
    ssh $node "$startNodeCMD"
done

# Start services
networkName="flink_network"
dockerCreate="docker service create --network $networkName"
# Create network -> Zookeeper -> Kafka -> Flink
docker network create --driver overlay $networkName

$dockerCreate --name zookeeper1 --publish 2181:2181 kaeblo/zookeeper
$dockerCreate --name kafka1 --publish 9092:9092  --replicas 3   kaeblo/kafka
$dockerCreate --name flink1     kaeblo/flink1
