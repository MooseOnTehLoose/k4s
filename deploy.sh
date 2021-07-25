#!/bin/bash

###################################
#Automatic HA deployment of K3s 
#
#Tony Windebank
###################################

#Deployment Options are: 1st Control Plane, Additional Control Plane, Agent
#
# ARG 1 - Role
# ARG 2 - User 
# ARG 3 - K3s Release
# ARG 4 - API Server Address
# ARG 5 - Node-Token


#role is either initserver, server or agent
role=$1

#user looks like twindebank
user=$2

#A release tag looks like v1.21.2+k3s1
release=$3

#API Server Address looks like https://10.4.6.201:6443
api_addr=$4

#Node-Token used to join the init-server 
token=$5

#The path to the local storage k3s will use for installation, inferred from the user path + data
data_dir=$(eval echo "~$user"/data)

#1 Ensure ~/data dir is scrubbed 
sudo rm -rf $data_dir/*

#2 Grab the specified k3s and install it
wget -O k3s https://github.com/k3s-io/k3s/releases/download/${release}/k3s-arm64
chmod a+x k3s && sudo mv k3s /usr/local/bin/k3s


#3 Evaluate Node Type
if [ $role = "initserver" ]
then
  node_service_type=notify
  exec_start="/usr/local/bin/k3s server --cluster-init --data-dir "${data_dir}" --node-taint CriticalAddonsOnly=true:NoExecute"
elif [ $role = "server" ]
then
  node_service_type=notify
  exec_start="/usr/local/bin/k3s server --server "${api_addr}" --data-dir "${data_dir}" --node-taint CriticalAddonsOnly=true:NoExecute --token "${token}
elif [ $role = "agent" ]
then
  node_service_type=exec
  exec_start="/usr/local/bin/k3s agent --server "${api_addr}" --data-dir "${data_dir}" --token "${token}
fi

#4 Create systemd unit

echo "[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target
After=network-online.target
[Install]
WantedBy=multi-user.target
[Service]
Type="${node_service_type}"
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
EnvironmentFile=-/etc/systemd/system/k3s.service.env
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart="${exec_start} | sudo tee /etc/systemd/system/k3s.service


#Enable and Start Service
sudo systemctl daemon-reload
sudo systemctl enable k3s
sudo systemctl start k3s

#Read kubectl until Node is ready, if a control plane
if [ $role != "agent"]
then
  not_ready=true
  while $not_ready
  do
    sleep 5
    node_name=$(hostname)
    ready=$($data_dir/data/current/bin/kubectl get nodes --field-selector metadata.name=$node_name --no-headers -o custom-columns=STATUS:status.conditions[-1].type)
    if [ $ready = "Ready" ]
    then
      not_ready=false
    fi
  done
fi
