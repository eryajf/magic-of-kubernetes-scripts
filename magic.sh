#!/bin/bash
#
#author:eryajf
#blog:www.eryajf.net
#time:2018-11
#version:v1
#

base_dir=$(pwd)
set -e
mkdir -p /opt/k8s/bin/ && cp $base_dir/config/environment.sh /opt/k8s/bin/
source /opt/k8s/bin/environment.sh

#
##set color##
echoRed() { echo $'\e[0;31m'"$1"$'\e[0m'; }
echoGreen() { echo $'\e[0;32m'"$1"$'\e[0m'; }
echoYellow() { echo $'\e[0;33m'"$1"$'\e[0m'; }
##set color##
#

Kcsh(){

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}"
    ssh root@${node_ip} "yum install -y epel-release conntrack ipvsadm ipset sysstat curl iptables libseccomp keepalived haproxy"
  # ssh root@${node_ip} "systemctl stop firewalld && systemctl disable firewalld"
    ssh root@${node_ip} "iptables -F && sudo iptables -X && sudo iptables -F -t nat && sudo iptables -X -t nat && iptables -P FORWARD ACCEPT"
    ssh root@${node_ip} "swapoff -a && sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab"
    scp $base_dir/config/Kcsh/hosts root@${node_ip}:/etc/hosts
    scp $base_dir/config/Kcsh/kubernetes.conf root@${node_ip}:/etc/sysctl.d/kubernetes.conf
    ssh root@${node_ip} "modprobe br_netfilter && modprobe ip_vs"
    ssh root@${node_ip} "sysctl -p /etc/sysctl.d/kubernetes.conf"
    ssh root@${node_ip} 'yum -y install wget ntpdate lrzsz curl rsync && ntpdate -u cn.pool.ntp.org && echo "* * * * * /usr/sbin/ntpdate -u cn.pool.ntp.org &> /dev/null" > /var/spool/cron/root'
    ssh root@${node_ip} 'mkdir -p /opt/k8s/bin && mkdir -p /etc/kubernetes/cert'
    ssh root@${node_ip} 'mkdir -p /etc/etcd/cert && mkdir -p /var/lib/etcd'
    scp $base_dir/config/environment.sh  root@${node_ip}:/opt/k8s/bin/
    ssh root@${node_ip} "chmod +x /opt/k8s/bin/*"
done
}

Kzs(){

cp $base_dir/pack/cfssljson_linux-amd64 /opt/k8s/bin/cfssljson
cp $base_dir/pack/cfssl_linux-amd64 /opt/k8s/bin/cfssl
cp $base_dir/pack/cfssl-certinfo_linux-amd64 /opt/k8s/bin/cfssl-certinfo
chmod +x /opt/k8s/bin/*
export PATH=/opt/k8s/bin:$PATH

cd $base_dir/config/Kzs/ && cfssl gencert -initca ca-csr.json | cfssljson -bare ca

for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}"
    scp $base_dir/config/Kzs/{ca*.pem,ca-config.json} root@${node_ip}:/etc/kubernetes/cert
done
}

Kctl(){

tar xf $base_dir/pack/kubernetes-client-linux-amd64.tar.gz -C $base_dir/config/Kctl/client
tar xf $base_dir/pack/kubernetes-server-linux-amd64.tar.gz -C $base_dir/config/Kctl/server
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}"
    scp $base_dir/config/Kctl/client/kubernetes/client/bin/kubectl root@${node_ip}:/opt/k8s/bin/
    scp $base_dir/config/Kctl/server/kubernetes/server/bin/* root@${node_ip}:/opt/k8s/bin/
    ssh root@${node_ip} "chmod +x /opt/k8s/bin/*"
done

source /opt/k8s/bin/environment.sh
cd $base_dir/config/Kctl/
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
  -ca-key=/etc/kubernetes/cert/ca-key.pem \
  -config=/etc/kubernetes/cert/ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin

# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/cert/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kubectl.kubeconfig

# 设置客户端认证参数
kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kubectl.kubeconfig

# 设置上下文参数
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=kubectl.kubeconfig

# 设置默认上下文
kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}"
    ssh root@${node_ip} "mkdir -p ~/.kube"
    scp $base_dir/config/Kctl/kubectl.kubeconfig root@${node_ip}:~/.kube/config
done
}

Ketcd(){

tar xf $base_dir/pack/etcd-v3.3.7-linux-amd64.tar.gz -C $base_dir/config/Ketcd
cd $base_dir/config/Ketcd
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
    -ca-key=/etc/kubernetes/cert/ca-key.pem \
    -config=/etc/kubernetes/cert/ca-config.json \
    -profile=kubernetes etcd-csr.json | cfssljson -bare etcd

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}"
    scp $base_dir/config/Ketcd/etcd-v3.3.7-linux-amd64/etcd* root@${node_ip}:/opt/k8s/bin
    ssh root@${node_ip} "chmod +x /opt/k8s/bin/*"
    ssh root@${node_ip} "mkdir -p /etc/etcd/cert"
    scp $base_dir/config/Ketcd/etcd*.pem root@${node_ip}:/etc/etcd/cert/
done

cat > etcd.service.template <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
User=root
Type=notify
WorkingDirectory=/var/lib/etcd/
ExecStart=/opt/k8s/bin/etcd \\
  --data-dir=/var/lib/etcd \\
  --name=##NODE_NAME## \\
  --cert-file=/etc/etcd/cert/etcd.pem \\
  --key-file=/etc/etcd/cert/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-cert-file=/etc/etcd/cert/etcd.pem \\
  --peer-key-file=/etc/etcd/cert/etcd-key.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --listen-peer-urls=https://##NODE_IP##:2380 \\
  --initial-advertise-peer-urls=https://##NODE_IP##:2380 \\
  --listen-client-urls=https://##NODE_IP##:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://##NODE_IP##:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

source /opt/k8s/bin/environment.sh
for (( i=0; i < 3; i++ ))
do
    cd $base_dir/config/Ketcd/
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" etcd.service.template > etcd-${NODE_IPS[i]}.service 
done

for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}"
    cd $base_dir/config/Ketcd/
    ssh root@${node_ip} "mkdir -p /var/lib/etcd" 
    scp $base_dir/config/Ketcd/etcd-${node_ip}.service root@${node_ip}:/etc/systemd/system/etcd.service
done

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echo ">>> ${node_ip}" 
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable etcd && systemctl start etcd" &
    sleep 3
    ssh root@${node_ip} "systemctl status etcd|grep Active"
done

echoYellow "检测etcd服务是否正常"
    ETCDCTL_API=3 /opt/k8s/bin/etcdctl \
    --endpoints=https://${node_ip}:2379 \
    --cacert=/etc/kubernetes/cert/ca.pem \
    --cert=/etc/etcd/cert/etcd.pem \
    --key=/etc/etcd/cert/etcd-key.pem endpoint health
}

Knet (){

tar xf $base_dir/pack/flannel-v0.10.0-linux-amd64.tar.gz -C $base_dir/config/Knet/flannel
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}" 
    scp $base_dir/config/Knet/flannel/{flanneld,mk-docker-opts.sh} root@${node_ip}:/opt/k8s/bin/
    ssh root@${node_ip} "chmod +x /opt/k8s/bin/*"
done

cd $base_dir/config/Knet
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
  -ca-key=/etc/kubernetes/cert/ca-key.pem \
  -config=/etc/kubernetes/cert/ca-config.json \
  -profile=kubernetes flanneld-csr.json | cfssljson -bare flanneld

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}" 
    ssh root@${node_ip} "mkdir -p /etc/flanneld/cert"
    scp $base_dir/config/Knet/flanneld*.pem root@${node_ip}:/etc/flanneld/cert
done

etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/cert/ca.pem \
  --cert-file=/etc/flanneld/cert/flanneld.pem \
  --key-file=/etc/flanneld/cert/flanneld-key.pem \
  set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'

source /opt/k8s/bin/environment.sh
cat > flanneld.service << EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
ExecStart=/opt/k8s/bin/flanneld \\
  -etcd-cafile=/etc/kubernetes/cert/ca.pem \\
  -etcd-certfile=/etc/flanneld/cert/flanneld.pem \\
  -etcd-keyfile=/etc/flanneld/cert/flanneld-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX} \\
  -iface=${VIP_IF}
ExecStartPost=/opt/k8s/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}" 
    scp $base_dir/config/Knet/flanneld.service root@${node_ip}:/etc/systemd/system/
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable flanneld && systemctl start flanneld"
    ssh root@${node_ip} "systemctl status flanneld|grep Active"
done
}

Kmaster (){

Kha(){

source /opt/k8s/bin/environment.sh
cat  > $base_dir/config/Kmaster/Kha/keepalived-master.conf <<EOF
global_defs {
    router_id lb-master-105
}

vrrp_script check-haproxy {
    script "killall -0 haproxy"
    interval 5
    weight -30
}

vrrp_instance VI-kube-master {
    state MASTER
    priority 120
    dont_track_primary
    interface ${VIP_IF}
    virtual_router_id 68
    advert_int 3
    track_script {
        check-haproxy
    }
    virtual_ipaddress {
        ${MASTER_VIP}
    }
}
EOF

cat  > $base_dir/config/Kmaster/Kha/keepalived-backup.conf <<EOF
global_defs {
    router_id lb-backup-105
}

vrrp_script check-haproxy {
    script "killall -0 haproxy"
    interval 5
    weight -30
}

vrrp_instance VI-kube-master {
    state BACKUP
    priority 110
    dont_track_primary
    interface ${VIP_IF}
    virtual_router_id 68
    advert_int 3
    track_script {
        check-haproxy
    }
    virtual_ipaddress {
        ${MASTER_VIP}
    }
}
EOF

scp $base_dir/config/Kmaster/Kha/keepalived-master.conf root@kube-node1:/etc/keepalived/keepalived.conf
scp $base_dir/config/Kmaster/Kha/keepalived-backup.conf root@kube-node2:/etc/keepalived/keepalived.conf
scp $base_dir/config/Kmaster/Kha/keepalived-backup.conf root@kube-node3:/etc/keepalived/keepalived.conf

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}" 
    scp $base_dir/config/Kmaster/Kha/haproxy.cfg root@${node_ip}:/etc/haproxy
    ssh root@${node_ip} "systemctl start haproxy"
    ssh root@${node_ip} "systemctl status haproxy|grep Active"
    ssh root@${node_ip} "netstat -lnpt|grep haproxy"
    ssh root@${node_ip} "systemctl start keepalived"
    ssh root@${node_ip} "systemctl status keepalived|grep Active"
done
}

Kapi(){

source /opt/k8s/bin/environment.sh
cd $base_dir/config/Kmaster/Kapi/
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
  -ca-key=/etc/kubernetes/cert/ca-key.pem \
  -config=/etc/kubernetes/cert/ca-config.json \
  -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes

cat > $base_dir/config/Kmaster/Kapi/kube-apiserver.service.template << EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=/opt/k8s/bin/kube-apiserver \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --anonymous-auth=false \\
  --experimental-encryption-provider-config=/etc/kubernetes/encryption-config.yaml \\
  --advertise-address=##NODE_IP## \\
  --bind-address=##NODE_IP## \\
  --insecure-port=0 \\
  --authorization-mode=Node,RBAC \\
  --runtime-config=api/all \\
  --enable-bootstrap-token-auth \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=${NODE_PORT_RANGE} \\
  --tls-cert-file=/etc/kubernetes/cert/kubernetes.pem \\
  --tls-private-key-file=/etc/kubernetes/cert/kubernetes-key.pem \\
  --client-ca-file=/etc/kubernetes/cert/ca.pem \\
  --kubelet-client-certificate=/etc/kubernetes/cert/kubernetes.pem \\
  --kubelet-client-key=/etc/kubernetes/cert/kubernetes-key.pem \\
  --service-account-key-file=/etc/kubernetes/cert/ca-key.pem \\
  --etcd-cafile=/etc/kubernetes/cert/ca.pem \\
  --etcd-certfile=/etc/kubernetes/cert/kubernetes.pem \\
  --etcd-keyfile=/etc/kubernetes/cert/kubernetes-key.pem \\
  --etcd-servers=${ETCD_ENDPOINTS} \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/kube-apiserver-audit.log \\
  --event-ttl=1h \\
  --alsologtostderr=true \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes \\
  --v=2
Restart=on-failure
RestartSec=5
Type=notify
User=root
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

for (( i=0; i < 3; i++ ))
do
    cd $base_dir/config/Kmaster/Kapi/
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" kube-apiserver.service.template > kube-apiserver-${NODE_IPS[i]}.service 
done

for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}" 
    ssh ${node_ip} "mkdir -p /etc/kubernetes/cert/"
    scp $base_dir/config/Kmaster/Kapi/kubernetes*.pem ${node_ip}:/etc/kubernetes/cert/
    scp $base_dir/config/Kmaster/Kapi/encryption-config.yaml ${node_ip}:/etc/kubernetes/
    ssh ${node_ip} "mkdir -p /var/log/kubernetes"
    scp $base_dir/config/Kmaster/Kapi/kube-apiserver-${node_ip}.service ${node_ip}:/etc/systemd/system/kube-apiserver.service
    ssh ${node_ip} "systemctl daemon-reload && systemctl enable kube-apiserver && systemctl start kube-apiserver" &
    sleep 10
    ssh root@${node_ip} "systemctl status kube-apiserver |grep 'Active:'"
done

sleep 10
kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes
}

Kmanage(){

source /opt/k8s/bin/environment.sh

cd $base_dir/config/Kmaster/Kmanage/
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
  -ca-key=/etc/kubernetes/cert/ca-key.pem \
  -config=/etc/kubernetes/cert/ca-config.json \
  -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/cert/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=kube-controller-manager.pem \
  --client-key=kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context system:kube-controller-manager \
  --cluster=kubernetes \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig

cat > $base_dir/config/Kmaster/Kmanage/kube-controller-manager.service << EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/opt/k8s/bin/kube-controller-manager \\
  --port=0 \\
  --secure-port=10252 \\
  --bind-address=127.0.0.1 \\
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/cert/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/cert/ca-key.pem \\
  --experimental-cluster-signing-duration=8760h \\
  --root-ca-file=/etc/kubernetes/cert/ca.pem \\
  --service-account-private-key-file=/etc/kubernetes/cert/ca-key.pem \\
  --leader-elect=true \\
  --feature-gates=RotateKubeletServerCertificate=true \\
  --controllers=*,bootstrapsigner,tokencleaner \\
  --horizontal-pod-autoscaler-use-rest-clients=true \\
  --horizontal-pod-autoscaler-sync-period=10s \\
  --tls-cert-file=/etc/kubernetes/cert/kube-controller-manager.pem \\
  --tls-private-key-file=/etc/kubernetes/cert/kube-controller-manager-key.pem \\
  --use-service-account-credentials=true \\
  --alsologtostderr=true \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes \\
  --v=2
Restart=on
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}" 
    scp $base_dir/config/Kmaster/Kmanage/kube-controller-manager*.pem root@${node_ip}:/etc/kubernetes/cert/
    scp $base_dir/config/Kmaster/Kmanage/kube-controller-manager.kubeconfig root@${node_ip}:/etc/kubernetes/
    scp $base_dir/config/Kmaster/Kmanage/kube-controller-manager.service root@${node_ip}:/etc/systemd/system/
    ssh root@${node_ip} "mkdir -p /var/log/kubernetes"
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable kube-controller-manager && systemctl start kube-controller-manager"
    ssh root@${node_ip} "systemctl status kube-controller-manager|grep Active"
done
}

Kscheduler(){

source /opt/k8s/bin/environment.sh
cd $base_dir/config/Kmaster/Kscheduler/
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
  -ca-key=/etc/kubernetes/cert/ca-key.pem \
  -config=/etc/kubernetes/cert/ca-config.json \
  -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler

kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/cert/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.pem \
  --client-key=kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context system:kube-scheduler \
  --cluster=kubernetes \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}" 
    scp $base_dir/config/Kmaster/Kscheduler/kube-scheduler.kubeconfig root@${node_ip}:/etc/kubernetes/
    scp $base_dir/config/Kmaster/Kscheduler/kube-scheduler.service root@${node_ip}:/etc/systemd/system/
    ssh root@${node_ip} "mkdir -p /var/log/kubernetes"
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable kube-scheduler && systemctl start kube-scheduler"
    ssh root@${node_ip} "systemctl status kube-scheduler|grep Active"
done
}

echoYellow "现在开始部署高可用组件haproxy & keepalived！"
Kha
sleep 3
echoYellow "现在开始部署kube-apiserver！"
Kapi
sleep 3
echoYellow "现在开始部署kube-controller-manager！"
Kmanage
sleep 3
echoYellow "现在开始部署kube-scheduler！"
Kscheduler
}

Kwork(){

Kdocker(){
source /opt/k8s/bin/environment.sh
tar xf $base_dir/pack/docker-18.03.1-ce.tgz -C $base_dir/config/Kwork/Kdocker/

cat > $base_dir/config/Kwork/Kdocker/docker.service << "EOF"
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
Environment="PATH=/opt/k8s/bin:/bin:/sbin:/usr/bin:/usr/sbin"
EnvironmentFile=-/run/flannel/docker
ExecStart=/opt/k8s/bin/dockerd --log-level=error $DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP $MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}" 
    scp $base_dir/config/Kwork/Kdocker/docker/docker*  root@${node_ip}:/opt/k8s/bin/
    ssh root@${node_ip} "chmod +x /opt/k8s/bin/*"
    scp $base_dir/config/Kwork/Kdocker/docker.service root@${node_ip}:/etc/systemd/system/
    ssh root@${node_ip} "mkdir -p /etc/docker/"
    scp $base_dir/config/Kwork/Kdocker/docker-daemon.json root@${node_ip}:/etc/docker/daemon.json
    ssh root@${node_ip} "/usr/sbin/iptables -F && /usr/sbin/iptables -X && /usr/sbin/iptables -F -t nat && /usr/sbin/iptables -X -t nat"
    ssh root@${node_ip} "/usr/sbin/iptables -P FORWARD ACCEPT"
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable docker && systemctl start docker"
    #ssh root@${node_ip} 'for intf in /sys/devices/virtual/net/docker0/brif/*; do echo 1 > $intf/hairpin_mode; done'
    #ssh root@${node_ip} "sysctl -p /etc/sysctl.d/kubernetes.conf"
    ssh root@${node_ip} "systemctl status docker|grep Active" && sleep 10
    ssh root@${node_ip} "/usr/sbin/ip addr show flannel.1 && /usr/sbin/ip addr show docker0"
done
}

Kkubelet(){

source /opt/k8s/bin/environment.sh
for node_name in ${NODE_NAMES[@]}
do
    echo ">>> ${node_name}" 
    cd $base_dir/config/Kwork/Kkubelet/
    # 创建 token
    export BOOTSTRAP_TOKEN=$(kubeadm token create \
      --description kubelet-bootstrap-token \
      --groups system:bootstrappers:${node_name} \
      --kubeconfig ~/.kube/config)

    # 设置集群参数
    kubectl config set-cluster kubernetes \
      --certificate-authority=/etc/kubernetes/cert/ca.pem \
      --embed-certs=true \
      --server=${KUBE_APISERVER} \
      --kubeconfig=kubelet-bootstrap-${node_name}.kubeconfig

    # 设置客户端认证参数
    kubectl config set-credentials kubelet-bootstrap \
      --token=${BOOTSTRAP_TOKEN} \
      --kubeconfig=kubelet-bootstrap-${node_name}.kubeconfig

    # 设置上下文参数
    kubectl config set-context default \
      --cluster=kubernetes \
      --user=kubelet-bootstrap \
      --kubeconfig=kubelet-bootstrap-${node_name}.kubeconfig

    # 设置默认上下文
    kubectl config use-context default --kubeconfig=kubelet-bootstrap-${node_name}.kubeconfig
done

source /opt/k8s/bin/environment.sh
for node_name in ${NODE_NAMES[@]}
do 
    echoGreen ">>> ${node_name}"
    cd $base_dir/config/Kwork/Kkubelet/
    sed -e "s/##NODE_NAME##/${node_name}/" kubelet.service.template > kubelet-${node_name}.service
    scp $base_dir/config/Kwork/Kkubelet/kubelet-${node_name}.service root@${node_name}:/etc/systemd/system/kubelet.service
    scp $base_dir/config/Kwork/Kkubelet/kubelet-bootstrap-${node_name}.kubeconfig root@${node_name}:/etc/kubernetes/kubelet-bootstrap.kubeconfig
done

kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --group=system:bootstrappers

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}"
    cd $base_dir/config/Kwork/Kkubelet/
    sed -e "s/##NODE_IP##/${node_ip}/" kubelet.config.json.template > kubelet.config-${node_ip}.json
    scp $base_dir/config/Kwork/Kkubelet/kubelet.config-${node_ip}.json root@${node_ip}:/etc/kubernetes/kubelet.config.json
    ssh root@${node_ip} "mkdir -p /var/lib/kubelet"
    ssh root@${node_ip} "/usr/sbin/swapoff -a"
    ssh root@${node_ip} "mkdir -p /var/log/kubernetes"
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable kubelet && systemctl restart kubelet"
    ssh root@${node_ip} "systemctl status kubelet | grep Active"
done

kubectl apply -f $base_dir/config/Kwork/Kkubelet/csr-crb.yaml
}

Kproxy(){

source /opt/k8s/bin/environment.sh
cd $base_dir/config/Kwork/Kproxy/
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
  -ca-key=/etc/kubernetes/cert/ca-key.pem \
  -config=/etc/kubernetes/cert/ca-config.json \
  -profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy

kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/cert/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

cat > $base_dir/config/Kwork/Kproxy/kube-proxy.config.yaml.template <<EOF
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: ##NODE_IP##
clientConnection:
  kubeconfig: /etc/kubernetes/kube-proxy.kubeconfig
clusterCIDR: ${CLUSTER_CIDR}
healthzBindAddress: ##NODE_IP##:10256
hostnameOverride: ##NODE_NAME##
kind: KubeProxyConfiguration
metricsBindAddress: ##NODE_IP##:10249
mode: "ipvs"
EOF

source /opt/k8s/bin/environment.sh
for (( i=0; i < 3; i++ ))
do 
    echoGreen ">>> ${NODE_NAMES[i]}"
    cd $base_dir/config/Kwork/Kproxy/
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" kube-proxy.config.yaml.template > kube-proxy-${NODE_NAMES[i]}.config.yaml
    scp $base_dir/config/Kwork/Kproxy/kube-proxy-${NODE_NAMES[i]}.config.yaml root@${NODE_NAMES[i]}:/etc/kubernetes/kube-proxy.config.yaml
done

source /opt/k8s/bin/environment.sh
for node_name in ${NODE_NAMES[@]}
do 
    echoGreen ">>> ${node_name}"
    scp $base_dir/config/Kwork/Kproxy/kube-proxy.kubeconfig root@${node_name}:/etc/kubernetes/
    scp $base_dir/config/Kwork/Kproxy/kube-proxy.service root@${node_name}:/etc/systemd/system/
done

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
do
    echoGreen ">>> ${node_ip}" 
    ssh root@${node_ip} "mkdir -p /var/lib/kube-proxy"
    ssh root@${node_ip} "mkdir -p /var/log/kubernetes"
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable kube-proxy && systemctl start kube-proxy"
    ssh root@${node_ip} "systemctl status kube-proxy|grep Active"
    ssh root@${node_ip} "/usr/sbin/ipvsadm -ln"
done
}
echoYellow "现在开始部署docker服务！"
Kdocker
sleep 3
echoYellow "现在开始部署kubelet服务！"
Kkubelet
sleep 3
echoYellow "现在开始部署kube-proxy服务！"
Kproxy
}

echoYellow "现在开始执行环境初始化工作！"
Kcsh
sleep 2
echoYellow "现在开始配置证书！"
Kzs
sleep 2
echoYellow "现在开始部署kubectl服务！"
Kctl
sleep 2
echoYellow "现在开始部署etcd服务！"
Ketcd
sleep 2
echoYellow "现在开始部署flannel网络服务！"
Knet
sleep 2
echoYellow "现在开始部署master组件！"
Kmaster
sleep 2
echoYellow "现在开始部署work组件！"
Kwork

echoRed "部署完成，现在可以享用k8s高可用集群各个功能了！"
