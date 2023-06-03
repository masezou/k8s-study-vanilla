#!/usr/bin/env bash
echo -e "\e[32mStarting $0 ....\e[m"
#########################################################
# kubeadm version
# Kubernetes version is refered in 1-tool.sh. If you want to set certain version, set this.
# 1.21.9-00 was tested also.
#KUBECTLVER=1.22.6-00

#Timezone
TIMEZONE="Etc/UTC"

# install as master
ENABLEK8SMASTER=1

# Enable private registry
ENABLEREG=1
REGDIR=/disk/registry
# Enable pull/push sample image
IMAGEDL=0

# Kubernetes Cluster name
CLUSTERNAME=$(hostname)-cl

# Enable sysstat
SYSSTAT=1

# REGISTRY Setting
#REGISTRY="${LOCALIPADDR}:5000"
#REGISTRYURL=http://${REGISTRY}

CONTAINERDVER=latest

#FORCE_LOCALIP=192.168.16.2
#########################################################

if [ ${EUID:-${UID}} != 0 ]; then
	echo "This script must be run as root"
	exit 1
else
	echo "I am root user."
fi

# HOSTNAME check
ping -c 3 $(hostname)
retvalping=$?
if [ ${retvalping} -ne 0 ]; then
	echo -e "\e[31m HOSTNAME was not configured correctly. \e[m"
	exit 255
fi

### Distribution Check ###
UBUNTUVER=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d "=" -f2)
case ${UBUNTUVER} in
"20.04")
	echo -e "\e[32m${UBUNTUVER} is OK. \e[m"
	;;
"22.04")
	echo "${UBUNTUVER} is OK.."
	#exit 255
	;;
*)
	echo -e "\e[31m${UBUNTUVER} is NG. \e[m"
	exit 255
	;;
esac

if [ ! -f /usr/share/doc/ubuntu-server/copyright ]; then
	echo -e "\e[31m It seemed his VM is installed Ubuntu Desktop media. VM which is installed from Ubuntu Desktop media is not supported. Please re-create VM from Ubuntu Server media! \e[m"
	exit 255
fi

### ARCH Check ###
PARCH=$(arch)
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
if [ -z ${FORCE_LOCALIP} ]; then
ETHDEV=`netplan get| sed 's/^[[:space:]]*//'  | grep -A 1 "ethernet" | grep -v ethernet | cut -d ":" -f 1`
LOCALIPADDR=`ip -f inet -o addr show $ETHDEV |cut -d\  -f 7 | cut -d/ -f 1`
else
	LOCALIPADDR=${FORCE_LOCALIP}
fi
if [ -z ${LOCALIPADDR} ]; then
	echo -e "\e[31m Local IP address setting was failed, please set FORCE_LOCALIP and re-run.  \e[m"
	exit 255
else
	echo ${LOCALIPADDR}
fi

if [ -z ${REGISTRY} ]; then
	REGISTRY="${LOCALIPADDR}:5000"
fi
if [ -z ${REGISTRYURL} ]; then
	REGISTRYURL=http://${REGISTRY}
fi

# SUDO Login
if [[ -z "${SUDO_USER}" ]]; then
	echo "You are root login."
else
	echo "You are sudo login."
fi
echo $SUDO_USER

# Restart service automatically
if [ -f /etc/needrestart/needrestart.conf ]; then
	grep "{restart} = 'a'" /etc/needrestart/needrestart.conf
	retvalneedrestart=$?
	if [ ${retvalneedrestart} -ne 0 ]; then
		cat <<'EOF' >>/etc/needrestart/needrestart.conf
$nrconf{restart} = 'a';
EOF
	fi
fi

## Hostname uppercase workaround
KBHOSTNAME=$(hostname)
hostnamectl set-hostname ${KBHOSTNAME,,}

#OS Setting : locale timezone
echo ${TIMEZONE} >/etc/timezone
timedatectl set-timezone $(cat /etc/timezone)
dpkg-reconfigure --frontend noninteractive tzdata
cat <<EOF >>/etc/environment
LANG=en_US.utf-8
LC_ALL=en_US.utf-8
EOF
source /etc/environment
source /etc/profile

# Base setting
sed -i -e 's@/swap.img@#/swap.img@g' /etc/fstab
swapoff -a
rm /swap.img
echo "vm.swappiness=0" | sudo tee --append /etc/sysctl.conf
apt -y install iptables arptables ebtables
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
update-alternatives --set arptables /usr/sbin/arptables-legacy
update-alternatives --set ebtables /usr/sbin/ebtables-legacy

# Install containerd
# Remove docker from snap and stop snapd
systemctl status snapd.service --no-pager
retvalsnap=$?
if [ ${retvalsnap} -eq 0 ]; then
	snap remove docker
	systemctl disable --now snapd
	systemctl disable --now snapd.socket
	systemctl disable --now snapd.seeded
	systemctl stop snapd
	apt -y remove --purge snapd gnome-software-plugin-snap
	apt -y autoremove
fi
# Remove docker. We will use containerd!!!!
apt -y purge purge docker docker-engine docker.io containerd runc podman

if [ ! -f /usr/bin/containerd ]; then
#	apt -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
#	curl --retry 10 --retry-delay 3 --retry-connrefused -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
#	apt-key fingerprint 0EBFCD88
apt -y install ca-certificates curl gnupg lsb-release
mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	cat <<EOF >/etc/apt/apt.conf.d/90_no_prompt
APT::Get::Assume-Yes "true";
APT::Get::force-yes "true";
EOF
#	if [ ${ARCH} = amd64 ]; then
#		add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
#	elif [ ${ARCH} = arm64 ]; then
#		add-apt-repository -y "deb [arch=arm64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
#	else
#		echo "${ARCH} platform is not supported"
#		exit 1
#	fi
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
	apt update

	if [ -z ${CONTAINERDVER} ]; then
		echo "Install containerd.io 1.4.13-1"
		apt -y install containerd.io=1.4.13-1
	else
		echo "Install containerd.io latest version"
		apt -y install containerd.io
	fi
	CTRVER=$(containerd -v | cut -d " " -f3)
	curl --retry 10 --retry-delay 3 --retry-connrefused -sS https://raw.githubusercontent.com/containerd/containerd/v${CTRVER}/contrib/autocomplete/ctr -o /etc/bash_completion.d/ctr

	# Install nerdctl (cmd version)
	if [ ! -f /usr/local/bin/nerdctl ]; then
		apt -y install uidmap
		NERDCTLVER=$(grep NERDCTLVER= 1-tools.sh | cut -d "=" -f2)
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/containerd/nerdctl/releases/download/v${NERDCTLVER}/nerdctl-${NERDCTLVER}-linux-${ARCH}.tar.gz
		tar xfz nerdctl-${NERDCTLVER}-linux-${ARCH}.tar.gz -C /usr/local/bin
		rm -rf nerdctl-${NERDCTLVER}-linux-${ARCH}.tar.gz
		nerdctl completion bash >/etc/bash_completion.d/nerdctl
	fi

	# Containerd settings
	containerd config default | sudo tee /etc/containerd/config.toml
	sed -i -e "s/SystemdCgroup = false/SystemdCgroup = true/g" /etc/containerd/config.toml

	dpkg -l | grep containerd | grep 1.4 >/dev/null
	retvalcd14=$?
	if [ ${retvalcd14} -eq 0 ]; then
		#sed -i -e "/^          \[plugins\.\"io\.containerd\.grpc\.v1\.cri\"\.containerd\.runtimes\.runc\.options\]$/a\            SystemdCgroup \= true" /etc/containerd/config.toml
		cat <<EOF >insert.txt
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${REGISTRY}"]
          endpoint = ["${REGISTRYURL}"]
EOF
		#sed -i -e "/^          endpoint \= \[\"https\:\/\/registry-1.docker.io\"\]$/r insert.txt" /etc/containerd/config.toml
		sed -i -e "/^      \[plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors\]$/r insert.txt" /etc/containerd/config.toml
		rm -rf insert.txt
	else
		sed -i -e 's@config_path = ""@config_path = "/etc/containerd/certs.d"@g' /etc/containerd/config.toml
		mkdir -p /etc/containerd/certs.d/docker.io
		cat <<EOF >/etc/containerd/certs.d/docker.io/hosts.toml
server = "https://docker.io"

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
EOF
		mkdir -p /etc/containerd/certs.d/${REGISTRY}
		cat <<EOF >/etc/containerd/certs.d/${REGISTRY}/hosts.toml
server = "${REGISTRYURL}"

[host."${REGISTRYURL}"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF
	fi
	systemctl restart containerd
	echo 0 >/proc/sys/kernel/hung_task_timeout_secs
fi

# Install Registry
if [ ! -f /usr/bin/docker-registry ]; then
	if [ ${ENABLEREG} -eq 1 ]; then
		echo "install private registry"
		mkdir -p ${REGDIR}
		ln -s ${REGDIR} /var/lib/docker-registry
		ufw allow 5000
		apt -y install docker-registry
		sed -i -e "s/  htpasswd/#  htpasswd/g" /etc/docker/registry/config.yml
		sed -i -e "s/    realm/#    realm/g" /etc/docker/registry/config.yml
		sed -i -e "s/    path/#    path/g" /etc/docker/registry/config.yml
		systemctl restart docker-registry
	fi
fi
# pull/push images
if [ ${IMAGEDL} -eq 1 ]; then
	ctr images pull --platform linux/${ARCH} docker.io/bitnami/bitnami-shell:10-debian-10-r158
	ctr images tag docker.io/bitnami/bitnami-shell:10-debian-10-r158 ${REGISTRY}/bitnami/bitnami-shell:10-debian-10-r158
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/bitnami/bitnami-shell:10-debian-10-r158
	ctr images rm docker.io/bitnami/bitnami-shell:10-debian-10-r158
	ctr images rm ${REGISTRY}/bitnami/bitnami-shell:10-debian-10-r158

	ctr images pull --platform linux/${ARCH} docker.io/bitnami/mongodb:4.4.8
	ctr images tag docker.io/bitnami/mongodb:4.4.8 ${REGISTRY}/bitnami/mongodb:4.4.8
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/bitnami/mongodb:4.4.8
	ctr images rm docker.io/bitnami/mongodb:4.4.8
	ctr images rm ${REGISTRY}/bitnami/mongodb:4.4.8

	ctr images pull --platform linux/${ARCH} docker.io/bitnami/mysql:8.0.30-debian-11-r27
	ctr images tag docker.io/bitnami/mysql:8.0.30-debian-11-r27 ${REGISTRY}/bitnami/mysql:8.0.30-debian-11-r27
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/bitnami/mysql:8.0.30-debian-11-r27
	ctr images rm docker.io/bitnami/mysql:8.0.30-debian-11-r27
	ctr images rm ${REGISTRY}/bitnami/mysql:8.0.30-debian-11-r27

	ctr images pull --platform linux/${ARCH} docker.io/bitnami/mariadb:10.6.10-debian-11-r6
	ctr images tag docker.io/bitnami/mariadb:10.6.10-debian-11-r6 ${REGISTRY}/bitnami/mariadb:10.6.10-debian-11-r6
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/bitnami/mariadb:10.6.10-debian-11-r6
	ctr images rm docker.io/bitnami/mariadb:10.6.10-debian-11-r6
	ctr images rm ${REGISTRY}/bitnami/mariadb:10.6.10-debian-11-r6

	ctr images pull --platform linux/${ARCH} docker.io/bitnami/wordpress:6.0.2-debian-11-r9
	ctr images tag docker.io/bitnami/wordpress:6.0.2-debian-11-r9 ${REGISTRY}/bitnami/wordpress:6.0.2-debian-11-r9
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/bitnami/wordpress:6.0.2-debian-11-r9
	ctr images rm docker.io/bitnami/wordpress:6.0.2-debian-11-r9
	ctr images rm ${REGISTRY}/bitnami/wordpress:6.0.2-debian-11-r9

	ctr images pull --platform linux/${ARCH} docker.io/bitnami/postgresql:14.5.0-debian-11-r24
	ctr images tag docker.io/bitnami/postgresql:14.5.0-debian-11-r24 ${REGISTRY}/bitnami/postgresql:14.5.0-debian-11-r24
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/bitnami/postgresql:14.5.0-debian-11-r24
	ctr images rm docker.io/bitnami/postgresql:14.5.0-debian-11-r24
	ctr images rm ${REGISTRY}/bitnami/postgresql:14.5.0-debian-11-r24

	ctr images pull --platform linux/${ARCH} quay.io/ifont/pacman-nodejs-app:latest
	ctr images tag quay.io/ifont/pacman-nodejs-app:latest ${REGISTRY}/ifont/pacman-nodejs-app:latest
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/ifont/pacman-nodejs-app:latest
	ctr images rm quay.io/ifont/pacman-nodejs-app:latest
	ctr images rm ${REGISTRY}/ifont/pacman-nodejs-app:latest

	ctr images pull --platform linux/${ARCH} docker.io/library/mysql:8.0.30
	ctr images tag docker.io/library/mysql:8.0.30 ${REGISTRY}/library/mysql:8.0.30
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/library/mysql:8.0.30
	ctr images rm docker.io/library/mysql:8.0.30
	ctr images rm ${REGISTRY}/library/mysql:8.0.30

	ctr images pull --platform linux/${ARCH} docker.io/library/wordpress:5.6.2-apache
	ctr images tag docker.io/library/wordpress:5.6.2-apache ${REGISTRY}/library/wordpress:5.6.2-apache
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/library/wordpress:5.6.2-apache
	ctr images rm docker.io/library/wordpress:5.6.2-apache
	ctr images rm ${REGISTRY}/library/wordpress:5.6.2-apache

	ctr images pull --platform linux/${ARCH} mcr.microsoft.com/mssql/server:2019-CU15-ubuntu-20.04
	ctr images tag mcr.microsoft.com/mssql/server:2019-CU15-ubuntu-20.04 ${REGISTRY}/mssql/server:2019-CU15-ubuntu-20.04
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/mssql/server:2019-CU15-ubuntu-20.04
	ctr images rm mcr.microsoft.com/mssql/server:2019-CU15-ubuntu-20.04
	ctr images rm ${REGISTRY}/mssql/server:2019-CU15-ubuntu-20.04

	ctr images pull --platform linux/${ARCH} docker.io/library/alpine:3.18.0
	ctr images tag docker.io/library/alpine:3.18.0 ${REGISTRY}/library/alpine:3.18.0
	ctr images push --platform linux/${ARCH} --plain-http ${REGISTRY}/library/alpine:3.18.0
	ctr images rm docker.io/library/alpine:3.18.0
	ctr images rm ${REGISTRY}/library/alpine:3.18.0

	echo "Registry result"
	curl -X GET ${REGISTRYURL}/v2/_catalog
	ctr images ls
fi

# Install Kubernetes
if [ ! -f /usr/bin/kubeadm ]; then
	## for containerd
	mkdir -p /etc/systemd/system/kubelet.service.d
	cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/0-containerd.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF

	dpkg -l kubectl
	retval=$?
	if [ ${retval} -ne 0 ]; then
		curl --retry 10 --retry-delay 3 --retry-connrefused -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
		apt-add-repository  "deb http://apt.kubernetes.io/ kubernetes-xenial main"
		apt update
	fi
	if [ -z ${KUBECTLVER} ]; then
		KUBEADMBASEVER=$(grep "KUBEBASEVER=" ./1-tools.sh | cut -d "=" -f2)
		echo "Install kuberneates latest version"
		KUBECTLVER=$(curl -s https://packages.cloud.google.com/apt/dists/kubernetes-xenial/main/binary-amd64/Packages | grep Version | awk '{print $2}' | sort -n -t "." -k 3 | uniq | grep ${KUBEADMBASEVER} | tail -1)
	fi
	echo "Kubernetes version: ${KUBECTLVER}"

	apt -y install -qy kubelet=${KUBECTLVER} kubectl=${KUBECTLVER} kubeadm=${KUBECTLVER}
	if [ ! -f /usr/bin/kubeadm ]; then
		echo -e "\e[31m kubeadm was not installed correctly. exit. \e[m"
		exit 255
	else
		apt-mark hold kubectl kubelet kubeadm
		kubeadm completion bash >/etc/bash_completion.d/kubeadm.sh
		if [ ! -f /etc/bash_completion.d/kubectl ]; then
			kubectl completion bash >/etc/bash_completion.d/kubectl
			source /etc/bash_completion.d/kubectl
			echo 'export KUBE_EDITOR=vi' >>~/.bashrc
		fi
	fi
fi

# CRICTL setting
cat <<EOF >/etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: true
EOF
echo "source <(crictl completion bash) " >>/etc/profile.d/crictl.sh

apt -y install keepalived
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
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

# Network filesystem client
apt -y install nfs-common

# iscsi initiator setting
sed -i -e "s/debian/debian.$(hostname)/g" /etc/iscsi/initiatorname.iscsi
systemctl restart iscsid.service

#########################################################################
# Create Single node Cluster
if [ ! -f /usr/bin/kubeadm ]; then
	echo -e "\e[31m kubeadm was not installed correctly. exit. \e[m"
	exit 255
else
	kubectl cluster-info
	retvalcluster=$?
	if [ ${retvalcluster} -ne 0 ]; then
		if [ ${ENABLEK8SMASTER} -eq 1 ]; then
			cat <<EOF >k8sconfig.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: "/var/run/containerd/containerd.sock"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
controlPlaneEndpoint: ${LOCALIPADDR}
clusterName: ${CLUSTERNAME}
networking:
  podSubnet: 10.244.0.0/16
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: "systemd"
protectKernelDefaults: true
EOF
			kubeadm init --config k8sconfig.yaml
			rm -rf k8sconfig.yaml
			mkdir -p $HOME/.kube
			cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
			chown $(id -u):$(id -g) $HOME/.kube/config
			export KUBECONFIG=$HOME/.kube/config
			#kubectl taint nodes --all node-role.kubernetes.io/master-
			#kubectl taint nodes $(hostname)  node-role.kubernetes.io/master:NoSchedule-
			kubectl taint nodes $(hostname) node-role.kubernetes.io/control-plane:NoSchedule-
            kubectl label node $(hostname) node-role.kubernetes.io/master=master
			kubectl label node $(hostname) node-role.kubernetes.io/worker=worker
		fi
	fi
fi

if [ ${SYSSTAT} -eq 1 ]; then
	apt -y install sysstat
	sed -i -e 's/ENABLED="false"/ENABLED="true"/g' /etc/default/sysstat
	systemctl restart sysstat.service
fi

# For Gitlab service account
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gitlab-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: gitlab
    namespace: kube-system
EOF

if [ -z $SUDO_USER ]; then
	echo "there is no sudo login"
else
	mkdir -p /home/${SUDO_USER}/.kube
	cp ~/.kube/config /home/${SUDO_USER}/.kube/
	chown -R ${SUDO_USER}:${SUDO_USER} /home/${SUDO_USER}/.kube/
	chmod 600 /home/${SUDO_USER}/.kube/config

	# copy scripts to user area
	cp -rf ../k8s-study-vanilla /home/${SUDO_USER}/
	chown -R ${SUDO_USER}:${SUDO_USER} /home/${SUDO_USER}/k8s-study-vanilla
	rm /home/${SUDO_USER}/k8s-study-vanilla/1-tools.sh
	rm /home/${SUDO_USER}/k8s-study-vanilla/2-buildk8s-lnx.sh
	rm /home/${SUDO_USER}/k8s-study-vanilla/3-configk8s.sh
	rm /home/${SUDO_USER}/k8s-study-vanilla/4-csi-storage.sh
	rm /home/${SUDO_USER}/k8s-study-vanilla/5-csi-vsphere.sh
fi

# Waiting for booting kubectl
sleep 10

#########################################################################

echo ""
echo "*************************************************************************************"
echo "Kubernetes ${KUBECTLVER} was installed"
kubeadm config images list
echo ""
kubectl cluster-info
echo "Kubeconfig was copied ${KUBECONFIGNAME}_kubeconfig"
kubectl get node -o wide
echo ""
echo "Registry data"
curl -X GET ${REGISTRYURL}/v2/_catalog
echo ""
echo "Next Step"
echo ""
echo -e "\e[32m Run ./3-configk8s.sh. \e[m"
echo ""

chmod -x $0
ls
