#!/usr/bin/env bash

#########################################################
# AMD64/ARM64 Linux would be worked
# Kubernetes client version
# 1.21.8-00 was tested also.
KUBECTLVER=1.22.6-00

# For Client use. Not to set in cluster environment.
CLIENT=0

#########################################################

if [ ${CLIENT} -eq 1 ]; then
DOCKER=1
# Only tested on amd64. arm64 is experimental
CLOUDUTILS=1
# Powershell
POWERSHELL=1
else
CLOUDUTILS=0
POWERSHELL=0
fi
# Govc
GOVC=1

### UID Check ###
if [ ${EUID:-${UID}} != 0 ]; then
    echo "This script must be run as root"
    exit 1
else
    echo "I am root user."
fi

### Distribution Check ###
lsb_release -d | grep Ubuntu | grep 20.04
DISTVER=$?
if [ ${DISTVER} = 1 ]; then
    echo "only supports Ubuntu 20.04 server"
    exit 1
else
    echo "Ubuntu 20.04=OK"
fi

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

# SUDO Login
if [[ -z "${SUDO_USER}" ]]; then
  echo "You are root login."
else
  echo "You are sudo login."
fi
echo $SUDO_USER

#########################################################

BASEPWD=`pwd`

apt update
apt -y upgrade

# Install kubectl
if [ ! -f /usr/bin/kubectl ]; then
apt update
apt -y install apt-transport-https gnupg2 curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
apt update
apt -y install -qy kubectl=${KUBECTLVER}
apt-mark hold kubectl
kubectl completion bash >/etc/bash_completion.d/kubectl
source /etc/bash_completion.d/kubectl
echo 'export KUBE_EDITOR=vi' >>~/.bashrc
fi

# Install etcd-client
apt -y install etcd-client
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://gist.githubusercontent.com/swynter-ladbrokes/9960fe1a1f2467bfe6e6/raw/7a92e7d92b68d67f958d28af880e6561037c33c1/etcdctl
mv etcdctl /etc/bash_completion.d/
source /etc/bash_completion.d/etcdctl

# Install kubectx and kubens
if [ ! -f /usr/local/bin/kubectx ]; then
KUBECTX=0.9.4
if [ ${ARCH} = amd64 ]; then
        CXARCH=$(uname -i)
fi
if [ ${ARCH} = arm64 ]; then
        CXARCH=arm64
fi
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX}/kubectx_v${KUBECTX}_linux_${CXARCH}.tar.gz
tar xfz kubectx_v${KUBECTX}_linux_${CXARCH}.tar.gz
mv kubectx /usr/local/bin/
chmod +x /usr/local/bin/kubectx
rm -rf LICENSE kubectx_v${KUBECTX}_linux_${CXARCH}.tar.gz
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://raw.githubusercontent.com/ahmetb/kubectx/master/completion/kubectx.bash
mv kubectx.bash /etc/bash_completion.d/
source /etc/bash_completion.d/kubectx.bash
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX}/kubens_v${KUBECTX}_linux_${CXARCH}.tar.gz
tar xfz kubens_v${KUBECTX}_linux_${CXARCH}.tar.gz
mv kubens /usr/local/bin/
chmod +x /usr/local/bin/kubens
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://raw.githubusercontent.com/ahmetb/kubectx/master/completion/kubens.bash
mv kubens.bash /etc/bash_completion.d/
source /etc/bash_completion.d/kubens.bash
rm -rf LICENSE kubens_v${KUBECTX}_linux_${CXARCH}.tar.gz
apt -y install fzf
fi

# Install kubecolor
if [ ! -f /usr/bin/go ]; then
apt -y install golang-go
export GOPATH=$HOME/go
echo 'export GOPATH=$HOME/go' >>/etc/profile
echo 'export PATH=$PATH:/usr/lib/go/bin:$GOPATH/bin' >>/etc/profile
export PATH=$PATH:/usr/lib/go/bin:$GOPATH/bin
fi
if [ ! -f /root/go/bin/kubecolor ]; then
go get github.com/dty1er/kubecolor/cmd/kubecolor
if [ -z $SUDO_USER ]; then
  echo "there is no sudo login"
else
  echo "Installing kubecolor to login user"
  sudo -u $SUDO_USER go get github.com/dty1er/kubecolor/cmd/kubecolor
fi
cat << EOF >> /etc/profile
command -v kubecolor >/dev/null 2>&1 && alias kubectl="kubecolor"
EOF
alias kubectl=kubecolor
fi

# Install Helm
if [ ! -f /usr/local/bin/helm ]; then
curl -s -O https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
bash ./get-helm-3
helm version
rm get-helm-3
helm completion bash > /etc/bash_completion.d/helm
source /etc/bash_completion.d/helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
fi

# Install Skaffold
if [ ! -f /usr/local/bin/skaffold ]; then
curl --retry 10 --retry-delay 3 --retry-connrefused -sS -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64 && chmod +x skaffold && sudo mv skaffold /usr/local/bin
skaffold completion bash >/etc/bash_completion.d/skaffold
source /etc/bash_completion.d/skaffold
fi

# Install Minio client
if [ ! -f /usr/local/bin/mc ]; then
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://dl.min.io/client/mc/release/linux-${ARCH}/mc
mv mc /usr/local/bin/
chmod +x /usr/local/bin/mc
echo "complete -C /usr/local/bin/mc mc" > /etc/bash_completion.d/mc.sh
/usr/local/bin/mc >/dev/null
fi

# Install govc
if [ ${GOVC} -eq 1 ]; then
if [ ! -f /usr/local/bin/govc ]; then
GOVCVER=v0.27.2
mkdir govcbin
if [ ${ARCH} = amd64 ]; then
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/vmware/govmomi/releases/download/${GOVCVER}/govc_$(uname -s)_$(uname -i).tar.gz
tar xfz govc_$(uname -s)_$(uname -i).tar.gz -C govcbin
rm govc_$(uname -s)_$(uname -i).tar.gz
fi

if [ ${ARCH} = arm64 ]; then
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/vmware/govmomi/releases/download/${GOVCVER}/govc_$(uname -s)_${ARCH}.tar.gz
tar xfz govc_$(uname -s)_${ARCH}.tar.gz -C govcbin
rm govc_$(uname -s)_${ARCH}.tar.gz
fi

mv govcbin/govc /usr/local/bin
rm -rf govcbin
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://raw.githubusercontent.com/vmware/govmomi/master/scripts/govc_bash_completion
mv govc_bash_completion /etc/bash_completion.d/
fi
fi

# Install powershell
if [ ${POWERSHELL} -eq 1 ]; then
if [ ${ARCH} = amd64 ]; then
if [ ! -f /usr/bin/pwsh ]; then
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
apt update
apt -y install powershell
fi
fi
if [ ${ARCH} = arm64 ]; then
curl --retry 10 --retry-delay 3 --retry-connrefused -sS -L https://aka.ms/InstallAzureCli | sudo bash
fi
fi

# Install Docker for client
if [ ${DOCKER} -eq 1 ]; then
if [ ! -f /usr/bin/docker ]; then
snap remove docker
apt -y purge docker docker.io
apt -y upgrade
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
apt -y install docker-ce-cli docker-ce
curl --retry 10 --retry-delay 3 --retry-connrefused -sS https://raw.githubusercontent.com/containerd/containerd/v1.4.12/contrib/autocomplete/ctr -o /etc/bash_completion.d/ctr
groupadd docker
if [ -z $SUDO_USER ]; then
  echo "there is no sudo login"
else
usermod -aG docker ${SUDO_USER}
fi
systemctl enable docker
systemctl daemon-reload
systemctl restart docker
# Install Docker Compose
if [ ! -f /usr/local/bin/docker-compose ]; then
DOCKERCOMPOSEVER=2.2.3
if [ ${ARCH} = amd64 ]; then
  curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/docker/compose/releases/download/v${DOCKERCOMPOSEVER}/docker-compose-linux-$(uname -i)
  mv docker-compose-linux-$(uname -i) /usr/local/bin/docker-compose
 elif [ ${ARCH} = arm64 ]; then
  curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/docker/compose/releases/download/v${DOCKERCOMPOSEVER}/docker-compose-linux-aarch64
  mv docker-compose-linux-aarch64 /usr/local/bin/docker-compose
 else
   echo "${ARCH} platform is not supported"
 exit 1
fi
chmod +x /usr/local/bin/docker-compose
curl --retry 10 --retry-delay 3 --retry-connrefused -sS -L https://raw.githubusercontent.com/docker/compose/1.29.2/contrib/completion/bash/docker-compose  -o /etc/bash_completion.d/docker-compose
fi
# Install kompose
if [ ! -f /usr/local/bin/kompose ]; then
KOMPOSEVER=1.26.1
curl --retry 10 --retry-delay 3 --retry-connrefused -sS -L https://github.com/kubernetes/kompose/releases/download/v${KOMPOSEVER}/kompose-linux-${ARCH} -o kompose
mv kompose /usr/local/bin/kompose
chmod +x /usr/local/bin/kompose
kompose completion bash > /etc/bash_completion.d/kompose
source /etc/bash_completion.d/kompose
fi
# Install Kind
KINDVER=0.11.1
if [ ! -f /usr/local/bin/kind ]; then
curl -s -Lo ./kind https://github.com/kubernetes-sigs/kind/releases/download/v${KINDVER}/kind-linux-${ARCH}
mv ./kind /usr/local/bin/kind
chmod +x /usr/local/bin/kind
kind completion bash > /etc/bash_completion.d/kind
source /etc/bash_completion.d/kind
fi
# Install minikube
if [ ! -f /usr/local/bin/minikube ]; then
apt -y install conntrack
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${ARCH}
install minikube-linux-${ARCH} /usr/local/bin/minikube
rm minikube-linux-${ARCH}
minikube completion bash > /etc/bash_completion.d/minikube
source /etc/bash_completion.d/minikube
fi
fi

# for client installation
echo -e "\e[31mk8s installation is prohibited if you install docker to this mathine. this script removes deploying k8s scripts. \e[m"
rm -rf 00Install-k8s.sh 0-minio.sh 2-buildk8s-lnx.sh 3-configk8s.sh 4-csi-storage.sh 5-csi-vsphere.sh

cp -rf ../k8s-study-vanilla /home/${SUDO_USER}/
rm /home/${SUDO_USER}/k8s-study-vanilla/1-tools.sh
chown -R ${SUDO_USER}:${SUDO_USER} /home/${SUDO_USER}/k8s-study-vanilla
fi

# Install Cloud Utility
if [ ${CLOUDUTILS} -eq 1 ]; then
# Iinstall aws/eksctl
if [ ! -f /usr/local/bin/aws ]; then
curl --retry 10 --retry-delay 3 --retry-connrefused -sS "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -i).zip" -o "awscliv2.zip"
apt -y install unzip
unzip -q awscliv2.zip
rm awscliv2.zip
./aws/install
rm -rf aws
echo "complete -C '/usr/local/bin/aws_completer' aws" > /etc/bash_completion.d/aws.sh
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin
eksctl completion bash > /etc/bash_completion.d/eksctl.sh
export EKSA_RELEASE="0.6.1" OS="$(uname -s | tr A-Z a-z)" RELEASE_NUMBER=3
curl "https://anywhere-assets.eks.amazonaws.com/releases/eks-a/${RELEASE_NUMBER}/artifacts/eks-a/v${EKSA_RELEASE}/${OS}/eksctl-anywhere-v${EKSA_RELEASE}-${OS}-amd64.tar.gz" \
    --silent --location \
    | tar xz ./eksctl-anywhere
sudo mv ./eksctl-anywhere /usr/local/bin/
fi

# Install aks
if [ ! -f /usr/bin/az ]; then
apt update
apt -y install apt-transport-https ca-certificates gnupg curl lsb-release
curl --retry 10 --retry-delay 3 --retry-connrefused -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | tee /etc/apt/sources.list.d/azure-cli.list
apt update && apt -y install azure-cli
fi

# Install gke
if [ ! -f /usr/bin/gcloud ]; then
apt -y install ca-certificates apt-transport-https gnupg
apt update
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl --retry 10 --retry-delay 3 --retry-connrefused -sS https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt -y update && apt -y install google-cloud-sdk
fi
fi

# Misc
if [ ! -f /usr/lib/postgresql/12/bin/pgbench ]; then
apt -y install postgresql-client postgresql-contrib mysql-client jq apache2-utils mongodb-clients lynx scsitools
systemctl stop postgresql
systemctl disable postgresql
# I want to use only pgbench!
cp /usr/lib/postgresql/12/bin/pgbench /tmp
apt -y remove postgresql-12
apt -y autoremove
mv /tmp/pgbench /usr/lib/postgresql/12/bin/
fi

if [ ! -f /usr/local/bin/k10tools ]; then
bash ./K0-kasten-tools.sh
fi

apt clean
# disable snapd
systemctl disable --now snapd
systemctl disable --now snapd.socket
systemctl disable --now snapd.seeded

echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "Kubernetes tools was installed in Ubuntu"
echo -e "\e[32m run source /etc/profile or re-login again \e[m"
echo ""
if [ ${CLOUDUTILS} -eq 1 ]; then
echo "You have installed cloud utility \(AWS/Azure/GCP\)"
echo "You need to configure cloud client"
echo "AWS: aws configure"
echo "gcloud: gcloud init"
fi
echo ""
if [ ${POWERSHELL} -eq 1 ]; then
echo "Az command"
echo "pwsh then Install\-Module -Name Az \-AllowClobber \-Scope CurrentUser"
echo "Powercli"
echo "pwsh then Install\-Module VMware.PowerCLI \-Scope CurrentUser"
fi
cd ${BASEPWD}
chmod -x $0
