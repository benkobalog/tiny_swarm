#!/bin/bash

# == helper functions ==
get_state() {
    read header
    read firstLine
    state=$(echo $firstLine | cut -f $1 -d ' ')
    echo $state
}

is_ready() {
    while [ $($1 | get_state $2) != $3 ]; do  echo "Waiting"; done 
}

wait_for_service_up() {
    is_ready "$1" 5 "Running"
}

wait_for_nodes_up() {
    lsOut=$(docker node ls)

    nrAll=$(echo "$lsOut" | wc -l)
    nrActive=$(echo "$lsOut" | grep Active | wc -l)

    echo $nrAll
    echo $nrActive
    if [ $((nrAll - 1)) != $nrActive ]; then
	echo "Waiting for nodes to be active"
	waitfor
    fi
}

# ======================
#set -x
localIP=$(ifconfig enp0s3 | grep -oP "inet addr:[0-9.]{7,15} " | cut -f 2 -d :)

# Start manager node
startNodeCMD=$(docker swarm init --advertise-addr $localIP | grep 'docker swarm join')

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

wait_for_nodes_up


# Start services
networkName="flink_network"
dockerCreate="docker service create --network $networkName"
# Create network -> Zookeeper -> Kafka -> Flink
docker network create --driver overlay $networkName

$dockerCreate --name zookeeper1 --publish 2181:2181 kaeblo/zookeeper

wait_for_service_up "docker service ps zookeeper1"

$dockerCreate --name kafka1 --publish 9092:9092  --replicas 3   kaeblo/kafka

wait_for_service_up "docker service ps kafka1"

# Map Flink's jobmanager's port to a different port, schema registry uses this port as well 
docker service create \
       -e JOB_MANAGER_RPC_ADDRESS=flink-jobmanager \
       -p 8089:8081 \
       --network $networkName \
       --name flink-jobmanager \
       flink jobmanager

wait_for_service_up "docker service ps flink-jobmanager"

docker service create \
       -e JOB_MANAGER_RPC_ADDRESS=flink-jobmanager \
       --network $networkName \
       --name flink-taskmanager \
       --replicas 3 \
       flink taskmanager 
