#!/usr/bin/env bash

#########################################################

# Kubernetes client version
KUBECTLVER=1.21.7-00

# for AKS/EKS/GKE installation
CLOUDUTILS=0
# For Tanzu Community edition client installation
TCE=0
# for docker in client side. 
DOCKER=0

GOVC=1
POWERSHELL=0

#########################################################
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

# Install kubectx and kubens
if [ ! -f /usr/local/bin/kubectx ]; then
KUBECTX=0.9.4
if [ ${ARCH} = amd64 ]; then
        CXARCH=x86_64
fi
curl -OL https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX}/kubectx_v${KUBECTX}_linux_${CXARCH}.tar.gz
tar xfz kubectx_v${KUBECTX}_linux_${CXARCH}.tar.gz
mv kubectx /usr/local/bin/
chmod +x /usr/local/bin/kubectx
rm -rf LICENSE kubectx_v${KUBECTX}_linux_${CXARCH}.tar.gz
curl -OL https://raw.githubusercontent.com/ahmetb/kubectx/master/completion/kubectx.bash
mv kubectx.bash /etc/bash_completion.d/
source /etc/bash_completion.d/kubectx.bash
curl -OL https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX}/kubens_v${KUBECTX}_linux_${CXARCH}.tar.gz
tar xfz kubens_v${KUBECTX}_linux_${CXARCH}.tar.gz
mv kubens /usr/local/bin/
chmod +x /usr/local/bin/kubens
curl -OL https://raw.githubusercontent.com/ahmetb/kubectx/master/completion/kubens.bash
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
  echo "installing kubecolor to login user"
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
curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-${ARCH} && \
install skaffold /usr/local/bin/
rm skaffold
skaffold completion bash >/etc/bash_completion.d/skaffold
source /etc/bash_completion.d/skaffold
fi

# Install Minio client
if [ ! -f /usr/local/bin/mc ]; then
curl -OL https://dl.min.io/client/mc/release/linux-${ARCH}/mc
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
curl -OL https://github.com/vmware/govmomi/releases/download/${GOVCVER}/govc_Linux_x86_64.tar.gz
tar xfz govc_Linux_x86_64.tar.gz -C govcbin
rm govc_Linux_x86_64.tar.gz
fi

if [ ${ARCH} = arm64 ]; then
curl -OL https://github.com/vmware/govmomi/releases/download/${GOVCVER}/govc_Linux_arm64.tar.gz
tar xfz govc_Linux_arm64.tar.gz -C govcbin
rm govc_Linux_arm64.tar.gz
fi

mv govcbin/govc /usr/local/bin
rm -rf govcbin
curl -OL https://raw.githubusercontent.com/vmware/govmomi/master/scripts/govc_bash_completion
mv govc_bash_completion /etc/bash_completion.d/
fi
fi

# Install powershell
if [ ${POWERSHELL} -eq 1 ]; then
if [ ${ARCH} = amd64 ]; then
if [ ! -f /usr/bin/pwsh ]; then
/usr/bin/pwsh
curl -OL https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
apt update
apt -y install powershell
fi
fi
if [ ${ARCH} = arm64 ]; then
curl -L https://aka.ms/InstallAzureCli | sudo bash
fi
fi

# Install Docker for client
if [ ${DOCKER} -eq 1 ]; then
if [ ! -f /usr/bin/docker ]; then
apt -y purge docker.io
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
groupadd docker
if [ -z $SUDO_USER ]; then
  echo "there is no sudo login"
else
usermod -g docker ${SUDO_USER}
fi
systemctl enable docker
systemctl daemon-reload
systemctl restart docker
DOCKERCOMPOSEVER=2.2.2
if [ ${ARCH} = amd64 ]; then
  curl -OL https://github.com/docker/compose/releases/download/v${DOCKERCOMPOSEVER}/docker-compose-linux-x86_64
  mv docker-compose-linux-x86_64 /usr/local/bin/docker-compose
 elif [ ${ARCH} = arm64 ]; then
  curl -OL https://github.com/docker/compose/releases/download/v${DOCKERCOMPOSEVER}/docker-compose-linux-aarch64
  mv docker-compose-linux-aarch64 /usr/local/bin/docker-compose
 else
   echo "${ARCH} platform is not supported"
 exit 1
fi
chmod +x /usr/local/bin/docker-compose
KINDVER=0.11.1
if [ ! -f /usr/local/bin/kind ]; then
curl -s -Lo ./kind https://github.com/kubernetes-sigs/kind/releases/download/v${KINDVER}/kind-linux-${ARCH}
chmod +x ./kind
mv ./kind /usr/local/bin/kind
kind completion bash > /etc/bash_completion.d/kind
source /etc/bash_completion.d/kind
fi

fi
# for client installation
echo "k8s installation is prohibited if you install docker to this mathine."
chmod -x 00Install-k8s.sh 0-minio.sh 1-tools.sh 2-buildk8s-lnx.sh 3-configk8s.sh 4-csi-storage.sh 5-csi-vsphere.sh
fi

# Install Cloud Utility
if [ ${CLOUDUTILS} -eq 1 ]; then
# Iinstall aws/eksctl
if [ ! -f /usr/local/bin/aws ]; then
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt -y install unzip
unzip awscliv2.zip
./aws/install
rm -rf aws
echo "complete -C '/usr/local/bin/aws_completer' aws" > /etc/bash_completion.d/aws.sh
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin
eksctl completion bash > /etc/bash_completion.d/eksctl.sh
fi

# Install aks
if [ ! -f /usr/bin/az ]; then
apt update
apt -y install apt-transport-https ca-certificates gnupg curl lsb-release
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | tee /etc/apt/sources.list.d/azure-cli.list
apt update && apt -y install azure-cli
fi

# Install gke
if [ ! -f /usr/bin/gcloud ]; then
apt -y install ca-certificates apt-transport-https gnupg
apt update
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt -y update && apt -y install google-cloud-sdk
fi
fi

# Install Tanzu Community Edition Utility
if [ ${TCE} -eq 1 ]; then
if [ ${ARCH} = amd64 ]; then
if [ ! -f /usr/local/bin/tanzu ]; then
TANZURELVER=0.9.1
cd /tmp
curl -OL https://github.com/vmware-tanzu/community-edition/releases/download/v${TANZURELVER}/tce-linux-amd64-v${TANZURELVER}.
tar.gz
tar xfz tce-linux-amd64-v${TANZURELVER}.tar.gz
rm  tce-linux-amd64-v${TANZURELVER}.tar.gz
cd tce-linux-amd64-v${TANZURELVER}
if [ ${EUID:-${UID}} = 0 ]; then
    echo "currenly I am root user."
    if [ -z $SUDO_USER ]; then
     echo "root direct login is not supported"
     exit 255
   else
     echo "root user via sudo"
   fi
fi
echo ok
if [ -z $SUDO_USER ]; then
  ./install.sh
else
  sudo -u $SUDO_USER ./install.sh
  sudo -u $SUDO_USER ssh-keygen -f ~/.ssh/id_rsa -t rsa -N "" -C "hogehoge@example.com"
  sudo -u $SUDO_USER cat ~/.ssh/id_rsa.pu
fi
cd ..
rm -rf tce-linux-amd64-v${TANZURELVER}
cd ${BASEPWD}
fi
fi
OCTANTVER=0.25.0
if [ ${ARCH} = amd64 ]; then
  curl -OL https://github.com/vmware-tanzu/octant/releases/download/v${OCTANTVER}/octant_${OCTANTVER}_Linux-64bit.deb
  dpkg -i octant_${OCTANTVER}_Linux-64bit.deb
  rm octant_${OCTANTVER}_Linux-64bit.deb
 elif [ ${ARCH} = arm64 ]; then
   https://github.com/vmware-tanzu/octant/releases/download/v${OCTANTVER}/octant_${OCTANTVER}_Linux-ARM64.deb
   dpkg -i octant_${OCTANTVER}_Linux-ARM64.deb
   rm octant_${OCTANTVER}_Linux-ARM64.deb
 else
   echo "${ARCH} platform is not supported"
 exit 1
fi
fi
if [ ${ARCH} = arm64 ]; then
echo "TCE is not supported on arm64
fi
fi
# Misc
apt -y install postgresql-client postgresql-contrib mysql-client jq apache2-utils mongodb-clients lynx scsitools
systemctl stop postgresql
systemctl disable postgresql
#I want to use only pgbench!
cp /usr/lib/postgresql/12/bin/pgbench /tmp
apt -y remove postgresql-12
apt -y autoremove
mv /tmp/pgbench /usr/lib/postgresql/12/bin/

bash ./K0-kasten-tools.sh


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
chmod -x ./1-tools.sh
