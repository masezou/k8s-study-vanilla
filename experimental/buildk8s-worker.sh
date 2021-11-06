#!/usr/bin/env bash

DOCKERVER="5:20.10.10~3-0~ubuntu-focal"
KUBECTLVER=1.21.6-00
PRIVATEREGISTRY="192.168.133.19:5000"


if [ ${EUID:-${UID}} != 0 ]; then
    echo "This script must be run as root"
    exit 1
else
    echo "I am root user."
fi
grep 20.04 /etc/lsb-release
UBUNTUCHECK=$?
if [ ${UBUNTUCHECK} != 0 ]; then
echo "NG"
exit 1
fi
echo "ok"

### ARCH Check ###
PARCH=`arch`
if [ ${PARCH} = aarch64 ]; then
  ARCH=arm64
  echo ${ARCH}
elif [ ${PARCH} = arm64 ]; then
  ARCH=arm64
  echo ${ARCH}
elif [ ${PARCH} = x86_64 ]; then
  ARCH=amd64
  echo ${ARCH}
else
  echo "${ARCH} platform is not supported"
  exit 1
fi

# Base setting
sed -i -e 's@/swap.img@#/swap.img@g' /etc/fstab
swapoff -a
echo "vm.swappiness=0" | sudo tee --append /etc/sysctl.conf
apt -y install iptables arptables ebtables
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
update-alternatives --set arptables /usr/sbin/arptables-legacy
update-alternatives --set ebtables /usr/sbin/ebtables-legacy

# Install Docker
apt -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
apt-key fingerprint 0EBFCD88
if [ ${ARCH} = amd64 ]; then
  add-apt-repository  "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
elif [ ${ARCH} = arm64 ]; then
  add-apt-repository  "deb [arch=arm64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
else
  echo "${ARCH} platform is not supported"
  exit 1
fi
apt update
apt -y purge docker.io
apt -y install docker-ce-cli=${DOCKERVER} docker-ce=${DOCKERVER} docker-ce-rootless-extras=${DOCKERVER}
apt-mark hold docker-ce-cli docker-ce docker-ce-rootless-extras
groupadd docker

for DOCKERUSER in `ls -1 /home | grep -v linuxbrew`; do
     echo ${DOCKERUSER}
     gpasswd -a ${DOCKERUSER} docker
done

mkdir /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "insecure-registries":["${PRIVATEREGISTRY}"] 
}
EOF
mkdir -p /etc/docker/certs.d
systemctl enable docker
systemctl daemon-reload
systemctl restart docker

mkdir -p ~/.docker
cat << EOF > ~/.docker/config.json
{
  "insecure-registries":["${PRIVATEREGISTRY}"]
}
EOF

dpkg -l kubectl
retval=$?
if [ ${retval} -ne 0 ]; then
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
apt update
fi

## for containerd
# avoid to showing docker-shim error messages in containerd environment
mkdir -p /etc/systemd/system/kubelet.service.d
cat << EOF | sudo tee  /etc/systemd/system/kubelet.service.d/0-containerd.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF

# Install Kubernetes
apt -y install -qy kubelet=${KUBECTLVER} kubectl=${KUBECTLVER} kubeadm=${KUBECTLVER}
apt-mark hold kubectl kubelet kubeadm

apt -y install keepalived
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Containerd commin settings
containerd config default | sudo tee /etc/containerd/config.toml
sed -i -e "/^          \[plugins\.\"io\.containerd\.grpc\.v1\.cri\"\.containerd\.runtimes\.runc\.options\]$/a\            SystemdCgroup \= true" /etc/containerd/config.toml
cat << EOF > insert.txt
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${PRIVATEREGISTRY}"]
          endpoint = ["http://${PRIVATEREGISTRY}"]
EOF

sed -i -e "/^          endpoint \= \[\"https\:\/\/registry-1.docker.io\"\]$/r insert.txt" /etc/containerd/config.toml
rm -rf insert.txt

systemctl restart containerd

# Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Set Kubernetes kernel params
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
vm.overcommit_memory = 1
vm.panic_on_oom = 0
kernel.panic = 10
kernel.panic_on_oops = 1
kernel.keys.root_maxkeys = 1000000
kernel.keys.root_maxbytes = 25000000
EOF
sysctl --system

# CRICTL setting
cat << EOF >>  /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: true
EOF
echo "source <(crictl completion bash) " >> /etc/profile.d/crictl.sh
curl https://raw.githubusercontent.com/containerd/containerd/main/contrib/autocomplete/ctr  -o /etc/bash_completion.d/ctr

#Network filesystem client
apt -y install nfs-common smbclient cifs-utils

# clean apt
apt clean

echo ""
echo "*************************************************************************************"
echo "Next Step"
echo ""
echo "Create token in Master node, then join this server"
echo ""

chmod -x ./buildk8s-worker.sh
