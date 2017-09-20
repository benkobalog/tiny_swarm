set -x

nodes="wnode@worker1 wnode@worker2"

remoteCMD="docker swarm leave"

# Start worker nodes
for node in $nodes
do
    ssh $node "$remoteCMD"
done

# Stop Manager Node
docker swarm leave --force
docker network rm flink_network
