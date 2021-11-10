#!/usr/bin/env bash

KUBECTLVER=1.21.6-00

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

#### LOCALIP #########
ip address show ens160 >/dev/null
retval=$?
if [ ${retval} -eq 0 ]; then
        LOCALIPADDR=`ip -f inet -o addr show ens160 |cut -d\  -f 7 | cut -d/ -f 1`
else
  ip address show ens192 >/dev/null
  retval2=$?
  if [ ${retval2} -eq 0 ]; then
        LOCALIPADDR=`ip -f inet -o addr show ens192 |cut -d\  -f 7 | cut -d/ -f 1`
  else
        LOCALIPADDR=`ip -f inet -o addr show eth0 |cut -d\  -f 7 | cut -d/ -f 1`
  fi
fi
echo ${LOCALIPADDR}


# Base setting
sed -i -e 's@/swap.img@#/swap.img@g' /etc/fstab
swapoff -a
echo "vm.swappiness=0" | sudo tee --append /etc/sysctl.conf
apt -y install iptables arptables ebtables
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
update-alternatives --set arptables /usr/sbin/arptables-legacy
update-alternatives --set ebtables /usr/sbin/ebtables-legacy

# Install containerd
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
apt -y purge docker.io docker-ce-cli docker-ce docker-ce-rootless-extras
apt -y install containerd.io

dpkg -l kubectl
retval=$?
if [ ${retval} -ne 0 ]; then
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
apt update
fi

## for containerd
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

# Containerd settings
containerd config default | sudo tee /etc/containerd/config.toml
sed -i -e "/^          \[plugins\.\"io\.containerd\.grpc\.v1\.cri\"\.containerd\.runtimes\.runc\.options\]$/a\            SystemdCgroup \= true" /etc/containerd/config.toml

cat << EOF > insert.txt
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${LOCALIPADDR}:5000"]
          endpoint = ["http://${LOCALIPADDR}:5000"]
EOF
sed -i -e "/^          endpoint \= \[\"https\:\/\/registry-1.docker.io\"\]$/r insert.txt" /etc/containerd/config.toml
rm -rf insert.txt
systemctl restart containerd
echo 0 > /proc/sys/kernel/hung_task_timeout_secs

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
apt -y install nfs-common

# clean apt
apt clean

echo ""
echo "*************************************************************************************"
echo "Next Step"
echo ""
echo "Master node:"
echo "kubeadm token create"
echo 'openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | \'
echo 'openssl dgst -sha256 -hex | sed 's/^.* //''
echo ""
echo "Worker node:"
echo "kubeadm join --token <token> <control-plane-host>:<control-plane-port> --discovery-token-ca-cert-hash sha256:<hash>   --cri-socket=/run/containerd/containerd.sock"
echo ""
chmod -x ./buildk8s-worker.sh
