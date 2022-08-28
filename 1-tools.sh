#!/usr/bin/env bash
echo -e "\e[32mStarting $0 ....\e[m"
#########################################################
# AMD64/ARM64 Linux would be worked.
# Kubernetes client version.
# Only supports 1.21, 1.22, 11.23.   1.24 is experimental.
KUBEBASEVER=1.23

# If you want to set certain version....
# 1.21.9-00 was tested also.
#KUBECTLVER=1.22.6-00

# For Client use. Not to set in cluster environment.
CLIENT=0
PORTAINER=1
#Client setting: When you set CLIENT=1, you can set DNS setting."
DNSDOMAINNAME=k8slab.internal
#DNSHOSTIP=192.168.16.2

# Force REGISTRY Setting
# If you haven't set Registry server, the registry server will set to NS server.
#REGISTRY="IPADDR:5000"
#REGISTRYURL=http://${REGISTRY}

MSSQLCMD=1
NTPSVR=1
TCE=0
TCECLI=0
OC=0
#########################################################

if [ ${CLIENT} -eq 1 ]; then
	dpkg -l kubeadm
	CLIENTCHK=$?
	if [ ${CLIENTCHK} -eq 0 ]; then
		echo -e "\e[31m Client tools is not able to install to kubernetes node host! \e[m"
		exit 255
	fi
	DOCKER=1
	NERDCTL=1
	# Only tested on amd64. arm64 is experimental
	CLOUDUTILS=1
	# Powershell
	POWERSHELL=1
else
	DOCKER=0
	NERDCTL=0
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

# HOSTNAME check
ping -c 3 $(hostname)
retvalping=$?
if [ ${retvalping} -ne 0 ]; then
	echo -e "\e[31m HOSTNAME was not configured correctly. \e[m"
	exit 255
fi
# Internet connectivity
ping -c 3 www.yahoo.co.jp
retvalping2=$?
if [ ${retvalping2} -ne 0 ]; then
	echo -e "\e[31m There is no internet connectivity. \e[m"
	exit 255
fi

### Distribution Check ###
UBUNTUVER=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d "=" -f2)
case ${UBUNTUVER} in
"20.04")
	echo -e "\e[32m${UBUNTUVER} is OK. \e[m"
	;;
"22.04")
	echo "${UBUNTUVER} is experimental."
	#exit 255
	;;
*)
	echo -e "\e[31m${UBUNTUVER} is NG. \e[m"
	exit 255
	;;
esac

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

# SUDO Login
if [[ -z "${SUDO_USER}" ]]; then
	echo "You are root login."
else
	echo "You are sudo login."
fi
echo $SUDO_USER

#########################################################

BASEPWD=$(pwd)

apt update
apt -y upgrade
#apt -y install git curl

if [ -z ${KUBECTLVER} ]; then
	echo "Install kubectl latest version"
	KUBECTLVER=$(curl -s https://packages.cloud.google.com/apt/dists/kubernetes-xenial/main/binary-amd64/Packages | grep Version | awk '{print $2}' | sort -n -t "." -k 3 | uniq | grep ${KUBEBASEVER} | tail -1)
fi
echo "Kubectl verson: ${KUBECTLVER}"

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
	if [ ! -f /usr/local/bin/kubectl-convert ]; then
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl-convert"
		install -o root -g root -m 0755 kubectl-convert /usr/local/bin/kubectl-convert
		rm ./kubectl-convert
	fi
fi

# Install kube-bench
if [ ! -f /usr/local/bin/kube-bench ]; then
	KUBEBENCHVER=0.6.8
	wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -
	curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/aquasecurity/kube-bench/releases/download/v${KUBEBENCHVER}/kube-bench_${KUBEBENCHVER}_linux_${ARCH}.deb
	dpkg -i kube-bench_${KUBEBENCHVER}_linux_${ARCH}.deb
	rm -rf kube-bench_${KUBEBENCHVER}_linux_${ARCH}.deb
fi

# Install trivy
if [ ${UBUNTUVER} = "20.04" ]; then
	#apt -y  install wget apt-transport-https gnupg lsb-release
	wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -
	echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | tee -a /etc/apt/sources.list.d/trivy.list
	apt update
	apt -y install trivy
fi

# Install etcd-client
if [ ! -f /usr/bin/etcdctl ]; then
	apt -y install etcd-client
	curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://gist.githubusercontent.com/swynter-ladbrokes/9960fe1a1f2467bfe6e6/raw/7a92e7d92b68d67f958d28af880e6561037c33c1/etcdctl
	mv etcdctl /etc/bash_completion.d/
	source /etc/bash_completion.d/etcdctl
fi

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
if [ ! -f /usr/local/bin/kubecolor ]; then
	KUBECOLORVER=0.0.20
	curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/hidetatz/kubecolor/releases/download/v${KUBECOLORVER}/kubecolor_${KUBECOLORVER}_$(uname -s)_$(arch).tar.gz
	mkdir ~/kubecolor
	tar xfz kubecolor_${KUBECOLORVER}_$(uname -s)_$(arch).tar.gz -C ~/kubecolor
	mv ~/kubecolor/kubecolor /usr/local/bin/
	chmod +x /usr/local/bin/kubecolor
	rm -rf kubecolor_${KUBECOLORVER}_$(uname -s)_$(arch).tar.gz ~/kubecolor
	cat <<EOF >>/etc/profile
command -v kubecolor >/dev/null 2>&1 && alias kubectl="kubecolor"
EOF
	alias kubectl=kubecolor
fi

# Install krew
if [ ! -d /root/.krew/store/ ]; then
	mkdir /tmp/krew.temp
	cat <<EOF >/tmp/krew.temp/krew-plugin.sh
#!/usr/bin/env bash
source /etc/profile.d/krew.sh
kubectl krew install ctx
kubectl krew install ns
kubectl krew install iexec
kubectl krew install status
kubectl krew install neat
kubectl krew install view-secret
kubectl krew install images
kubectl krew install rolesum
kubectl krew install open-svc

kubectl krew install tree
kubectl krew install exec-as
kubectl krew install modify-secret
kubectl krew install view-serviceaccount-kubeconfig
kubectl krew install get-all
kubectl krew install node-shell
kubectl krew install ca-cert
kubectl krew install who-can

kubectl krew install outdated
kubectl krew install df-pv
kubectl krew install resource-capacity
kubectl krew install fleet
kubectl krew install prompt

kubectl krew install minio
kubectl krew install directpv

kubectl krew list
EOF
	chmod +x /tmp/krew.temp/krew-plugin.sh
	cd /tmp/krew.temp
	OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
		KREW="krew-${OS}_${ARCH}" &&
		curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
		tar zxvf "${KREW}.tar.gz"
	chmod ugo+x ./"${KREW}"
	./"${KREW}" install krew
	cat <<'EOF' >>/etc/profile.d/krew.sh
export PATH="$HOME/.krew/bin:$PATH"
EOF
	/tmp/krew.temp/krew-plugin.sh
	if [ -z $SUDO_USER ]; then
		echo "there is no sudo login"
	else
		sudo -u $SUDO_USER ./"${KREW}" install krew
		sudo -u $SUDO_USER /tmp/krew.temp/krew-plugin.sh
	fi
	unset OS
	unset KREW
	cd ${BASEPWD}
	rm -rf /tmp/krew.temp
fi

# Install Helm
if [ ! -f /usr/local/bin/helm ]; then
	curl -s -O https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
	bash ./get-helm-3
	helm version
	rm get-helm-3
	helm completion bash >/etc/bash_completion.d/helm
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
	echo "complete -C /usr/local/bin/mc mc" >/etc/bash_completion.d/mc.sh
	/usr/local/bin/mc >/dev/null
fi

# Install govc
if [ ${GOVC} -eq 1 ]; then
	if [ ! -f /usr/local/bin/govc ]; then
		GOVCVER=0.29.0
		mkdir govcbin
		if [ ${ARCH} = amd64 ]; then
			curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/vmware/govmomi/releases/download/v${GOVCVER}/govc_$(uname -s)_$(uname -i).tar.gz
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

# Install NTP Server
if [ ${NTPSVR} -eq 1 ]; then
	apt -y install ntp
	sed -i -e "s/pool 0.ubuntu/pool 0.jp/g" /etc/ntp.conf
	sed -i -e "s/pool 1.ubuntu/pool 1.jp/g" /etc/ntp.conf
	sed -i -e "s/pool 2.ubuntu/pool 2.jp/g" /etc/ntp.conf
	sed -i -e "s/pool 3.ubuntu/pool 3.jp/g" /etc/ntp.conf
	sed -i -e "s/pool ntp.ubuntu.com/pool ntp.nict.jp iburst/g" /etc/ntp.conf
	systemctl enable ntp
	systemctl restart ntp
	ntpq -p
fi

# MSSQL Client
if [ ${UBUNTUVER} = "20.04" ]; then
	if [ $MSSQLCMD -eq 1 ]; then
		if [ ! -f /opt/mssql-tools/bin/sqlcmd ]; then
			if [ ${ARCH} = amd64 ]; then
				curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://packages.microsoft.com/config/ubuntu/${UBUNTUVER}/packages-microsoft-prod.deb
				dpkg -i packages-microsoft-prod.deb
				rm packages-microsoft-prod.deb
				apt update
				ACCEPT_EULA=Y apt -y install mssql-tools unixodbc-dev
				echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >>/etc/profile.d/mssql.sh
			fi
		fi
	fi

	# Install powershell
	if [ ${POWERSHELL} -eq 1 ]; then
		if [ ${ARCH} = amd64 ]; then
			if [ ! -f /usr/bin/pwsh ]; then
				curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://packages.microsoft.com/config/ubuntu/${UBUNTUVER}/packages-microsoft-prod.deb
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
fi

# Install Docker for client
if [ ${DOCKER} -eq 1 ]; then
	if [ ! -f /usr/bin/docker ]; then
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
		# Remove docker from Ubuntu
		apt -y purge docker docker.io
		apt -y upgrade
		apt -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
		apt-key fingerprint 0EBFCD88
		cat <<EOF >/etc/apt/apt.conf.d/90_no_prompt
APT {
    Get {
        force-yes "true";
    };
};
EOF
		if [ ${ARCH} = amd64 ]; then
			add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
		elif [ ${ARCH} = arm64 ]; then
			add-apt-repository "deb [arch=arm64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)  stable"
		else
			echo "${ARCH} platform is not supported"
			exit 1
		fi
		apt -y install docker-ce-cli docker-ce
		CONTAINERDVER=$(/usr/bin/containerd -v | cut -d " " -f3)
		curl --retry 10 --retry-delay 3 --retry-connrefused -sS https://raw.githubusercontent.com/containerd/containerd/v${CONTAINERDVER}/contrib/autocomplete/ctr -o /etc/bash_completion.d/ctr
		groupadd docker
		if [ -z $SUDO_USER ]; then
			echo "there is no sudo login"
		else
			usermod -aG docker ${SUDO_USER}
			sudo -u $SUDO_USER mkdir -p /home/${SUDO_USER}/.docker
		fi

		# Install nerdctl (Full version)
		if [ ${NERDCTL} -eq 1 ]; then
			if [ ! -f /usr/local/bin/nerdctl ]; then
				apt -y install uidmap
				NERDCTLVER=0.19.0
				curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/containerd/nerdctl/releases/download/v${NERDCTLVER}/nerdctl-full-${NERDCTLVER}-linux-${ARCH}.tar.gz
				tar xfz nerdctl-full-${NERDCTLVER}-linux-${ARCH}.tar.gz -C /usr/local
				rm -rf nerdctl-full-${NERDCTLVER}-linux-${ARCH}.tar.gz
				nerdctl completion bash >/etc/bash_completion.d/nerdctl
				sed -i -e 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1"/g' /etc/default/grub
				update-grub
				mkdir -p /etc/systemd/system/user@.service.d
				cat <<EOF | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
[Service]
Delegate=cpu cpuset io memory pids
EOF
				systemctl daemon-reload
			fi
		fi

		if [ -z ${REGISTRY} ]; then
			REGISTRYIP=$(host -t a ${DNSDOMAINNAME} | cut -d " " -f4)
			echo ${REGISTRYIP} | grep out
			retvalregcheck=$?

			if [ ${retvalregcheck} -eq 0 ]; then
				REGISTRYIP=127.0.0.1
			fi
			REGISTRY="${REGISTRYIP}:5000"

			if [ -z ${REGISTRYURL} ]; then
				REGISTRYURL=http://${REGISTRY}
			fi

			mkdir -p /etc/docker/certs.d/${REGISTRY}
			cat <<EOF >/etc/docker/daemon.json
{ "insecure-registries":["${REGISTRY}"] }
EOF
		else
			cat <<EOF >/etc/docker/daemon.json.orig
{ "insecure-registries":["127.0.0.1:5000"] }
EOF
		fi

	fi

	systemctl enable docker
	systemctl daemon-reload
	systemctl restart docker

	#Portainer CE
	if [ ${PORTAINER} -eq 1 ]; then
		#nerdctl volume create portainer_data
		docker volume create portainer_data
		docker run -d -p 8001:8001 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce
	#nerdctl run -d -p 8001:8001 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce
	fi

	if [ ${DOCKER} -eq 1 ]; then
		containerd config default | sudo tee /etc/containerd/config.toml
		dpkg -l | grep containerd | grep 1.4 >/dev/null
		retvalcd14=$?
		if [ ${retvalcd14} -eq 0 ]; then
			if [ ! -z ${REGISTRY} ]; then
				cat <<EOF >insert.txt
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${REGISTRY}"]
          endpoint = ["${REGISTRYURL}"]
EOF
				sed -i -e "/^          endpoint \= \[\"https\:\/\/registry-1.docker.io\"\]$/r insert.txt" /etc/containerd/config.toml
				rm -rf insert.txt
			fi
		else
			sed -i -e 's@config_path = ""@config_path = "/etc/containerd/certs.d"@g' /etc/containerd/config.toml
			mkdir -p /etc/containerd/certs.d/docker.io
			cat <<EOF >/etc/containerd/certs.d/docker.io/hosts.toml
server = "https://docker.io"

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
EOF
			if [ ! -z ${REGISTRY} ]; then
				mkdir -p /etc/containerd/certs.d/${REGISTRY}
				cat <<EOF >/etc/containerd/certs.d/${REGISTRY}/hosts.toml
server = "${REGISTRYURL}"

[host."${REGISTRYURL}"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF
			fi
		fi
		systemctl restart containerd.service
	fi
	# Install Docker Compose
	if [ ! -f /usr/local/bin/docker-compose ]; then
		DOCKERCOMPOSEVER=2.10.2
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
		curl --retry 10 --retry-delay 3 --retry-connrefused -sS -L https://raw.githubusercontent.com/docker/compose/1.29.2/contrib/completion/bash/docker-compose -o /etc/bash_completion.d/docker-compose
	fi
	# Install kompose
	if [ ! -f /usr/local/bin/kompose ]; then
		KOMPOSEVER=1.26.1
		curl --retry 10 --retry-delay 3 --retry-connrefused -sS -L https://github.com/kubernetes/kompose/releases/download/v${KOMPOSEVER}/kompose-linux-${ARCH} -o kompose
		mv kompose /usr/local/bin/kompose
		chmod +x /usr/local/bin/kompose
		kompose completion bash >/etc/bash_completion.d/kompose
		source /etc/bash_completion.d/kompose
	fi
	# Install Kind
	if [ ! -f /usr/local/bin/kind ]; then
		KINDVER=0.12.0
		curl -s -Lo ./kind https://github.com/kubernetes-sigs/kind/releases/download/v${KINDVER}/kind-linux-${ARCH}
		mv ./kind /usr/local/bin/kind
		chmod +x /usr/local/bin/kind
		kind completion bash >/etc/bash_completion.d/kind
		source /etc/bash_completion.d/kind
	fi
	# Install minikube
	if [ ! -f /usr/local/bin/minikube ]; then
		apt -y install conntrack
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${ARCH}
		install minikube-linux-${ARCH} /usr/local/bin/minikube
		rm minikube-linux-${ARCH}
		minikube completion bash >/etc/bash_completion.d/minikube
		source /etc/bash_completion.d/minikube
	fi
fi

# for client network setting
if [ ${CLIENT} -eq 0 ]; then
	if [ -z ${DNSHOSTIP} ]; then
		DNSHOSTIP=$(host -t a ${DNSDOMAINNAME} | cut -d " " -f4)
		echo ${DNSHOSTIP} | grep out
		retvaldnsip=$?
		if [ ${retvaldnsip} -eq 0 ]; then
			unset DNSHOSTIP
			unset DNSDOMAINNAME
		fi
	fi
	if [ ! -z ${DNSHOSTIP} ]; then
		ETHDEV=$(grep ens /etc/netplan/00-installer-config.yaml | tr -d ' ' | cut -d ":" -f1)
		netplan set network.ethernets.${ETHDEV}.nameservers.addresses=[${DNSHOSTIP}]
		netplan apply
	fi
	if [ ! -z ${DNSDOMAINNAME} ]; then
		ETHDEV=$(grep ens /etc/netplan/00-installer-config.yaml | tr -d ' ' | cut -d ":" -f1)
		netplan set network.ethernets.${ETHDEV}.nameservers.search=[${DNSDOMAINNAME}]
		netplan apply
	fi
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
		echo "complete -C '/usr/local/bin/aws_completer' aws" >/etc/bash_completion.d/aws.sh
		curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
		mv /tmp/eksctl /usr/local/bin
		eksctl completion bash >/etc/bash_completion.d/eksctl.sh
		export EKSA_RELEASE="0.6.1" OS="$(uname -s | tr A-Z a-z)" RELEASE_NUMBER=3
		curl "https://anywhere-assets.eks.amazonaws.com/releases/eks-a/${RELEASE_NUMBER}/artifacts/eks-a/v${EKSA_RELEASE}/${OS}/eksctl-anywhere-v${EKSA_RELEASE}-${OS}-amd64.tar.gz" \
			--silent --location |
			tar xz ./eksctl-anywhere
		sudo mv ./eksctl-anywhere /usr/local/bin/
	fi

	# Install aks
	if [ ! -f /usr/bin/az ]; then
		apt update
		apt -y install apt-transport-https ca-certificates gnupg curl lsb-release
		curl --retry 10 --retry-delay 3 --retry-connrefused -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null
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

# Installing golang
if [ ! -f /usr/bin/go ]; then
	apt -y install golang
fi
if [ ! -f /usr/local/bin/k10tools ]; then
	if [ -f ./K0-kasten-tools.sh ]; then
		echo "Installing k10tools"
		bash ./K0-kasten-tools.sh
	fi
fi

apt -y autoremove
apt clean
# disable snapd
systemctl status snapd.service --no-pager
retvalsnap=$?
if [ ${retvalsnap} -eq 0 ]; then
	systemctl disable --now snapd
	systemctl disable --now snapd.socket
	systemctl disable --now snapd.seeded
	systemctl stop snapd
	apt -y remove --purge snapd gnome-software-plugin-snap

fi

# Install cfssljson - openssl alternative
if [ ${ARCH} = amd64 ]; then
	CFSSLVER=1.6.1
	if [ ! -f /usr/local/bin/cfssl ]; then
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/cloudflare/cfssl/releases/download/v${CFSSLVER}/cfssl_${CFSSLVER}_linux_${ARCH}
		mv cfssl_${CFSSLVER}_linux_${ARCH} /usr/local/bin/cfssl
		chmod +x /usr/local/bin/cfssl
	fi
	if [ ! -f /usr/local/bin/cfssljson ]; then
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/cloudflare/cfssl/releases/download/v${CFSSLVER}/cfssljson_${CFSSLVER}_linux_${ARCH}
		mv cfssljson_${CFSSLVER}_linux_${ARCH} /usr/local/bin/cfssljson
		chmod +x /usr/local/bin/cfssljson
	fi
fi

# I like vi in less.
echo "export VISUAL=vi" >/etc/profile.d/less-pager.sh

# Install tanzu tools
if [ ${TCE} -eq 1 ]; then

	# Install Velero
	if [ ! -f /usr/local/bin/velero ]; then
		VELEROVER=1.8.1
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/vmware-tanzu/velero/releases/download/v${VELEROVER}/velero-v${VELEROVER}-linux-${ARCH}.tar.gz
		tar xfz velero-v${VELEROVER}-linux-${ARCH}.tar.gz
		mv velero-v${VELEROVER}-linux-${ARCH}/velero /usr/local/bin/
		rm velero-v${VELEROVER}-linux-${ARCH}.tar.gz
		velero completion bash >/etc/bash_completion.d/velero
	fi

	# Install imgpkg
	if [ ! -f /usr/local/bin/imgpkg ]; then
		IMGPKGVER=0.28.0
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/vmware-tanzu/carvel-imgpkg/releases/download/v${IMGPKGVER}/imgpkg-linux-${ARCH}
		mv imgpkg-linux-${ARCH} /usr/local/bin/imgpkg
		chmod +x /usr/local/bin/imgpkg
		imgpkg completion bash >/etc/bash_completion.d/imgpkg
	fi

	# Install yq
	if [ ! -f /usr/local/bin/yq ]; then
		YQVER=4.25.1
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/mikefarah/yq/releases/download/v${YQVER}/yq_linux_${ARCH}
		mv yq_linux_${ARCH} /usr/local/bin/yq
		chmod +x /usr/local/bin/yq
		yq shell-completion bash >/etc/bash_completion.d/yq
	fi

	# Install Octant
	if [ ! -f /usr/local/bin/octant ]; then
		OCTANTVER=0.26.1
		if [ ${ARCH} = amd64 ]; then
			curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/vmware-tanzu/octant/releases/download/v${OCTANTVER}/octant_${OCTANTVER}_$(uname -s)-64bit.deb
			dpkg -i octant_${OCTANTVER}_$(uname -s)-64bit.deb
			rm octant_${OCTANTVER}_$(uname -s)-64bit.deb
		elif [ ${ARCH} = arm64 ]; then
			curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/vmware-tanzu/octant/releases/download/v${OCTANTVER}/octant_${OCTANTVER}_$(uname -s)-ARM64.deb
			dpkg -i octant_${OCTANTVER}_$(uname -s)-ARM64.deb
			rm octant_${OCTANTVER}_$(uname -s)-ARM64.deb
		else
			echo "${ARCH} platform is not supported"
		fi
		echo "export OCTANT_LISTENER_ADDR=0.0.0.0:8090" >/etc/profile.d/octant.sh
		echo "export OCTANT_DISABLE_OPEN_BROWSER=true" >>/etc/profile.d/octant.sh
	fi

	if [[ -z "${SUDO_USER}" ]]; then
		echo "there is no sudo login"
	else
		if [ ${ARCH} = "amd64" ]; then
			sudo -u $SUDO_USER mkdir -p ~/.config/octant/plugins/ &&
				OCTANT_HELMVER=0.2.0
			sudo -u $SUDO_USER curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/bloodorangeio/octant-helm/releases/download/v${OCTANT_HELMVER}/octant-helm_${OCTANT_HELMVER}_linux_${ARCH}.tar.gz | tar xz -C ~/.config/octant/plugins/ octant-helm
			cd /tmp
			OCTANT_KINDVER=0.0.1
			sudo -u $SUDO_USER curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/vmware-tanzu/octant-plugin-for-kind/releases/download/v${OCTANT_KINDVER}/octant-plugin-for-kind_${OCTANT_KINDVER}_Linux-64bit.tar.gz
			sudo -u $SUDO_USER tar xfz octant-plugin-for-kind_${OCTANT_KINDVER}_Linux-64bit.tar.gz
			sudo -u $SUDO_USER mv octant-plugin-for-kind_${OCTANT_KINDVER}_Linux-64bit/octant ~/.config/octant/plugins/octant-kind
			rm -rf octant-plugin-for-kind_${OCTANT_KINDVER}_Linux-64bit*
			sudo -u $SUDO_USER git clone https://github.com/ashish-amarnath/octant-velero-plugin --depth 1
			sudo -u $SUDO_USER cd octant-velero-plugin
			apt -y install make
			sudo -u $SUDO_USER make install
			cd ..
			rm -rf octant-velero-plugin
			cd ${BASEPWD}
		fi
	fi

fi

if [ ${TCECLI} -eq 1 ]; then
	if [ ${DOCKER} -eq 1 ]; then
		if [ ${ARCH} = "amd64" ]; then
			if [ ! -f /usr/local/bin/tanzu ]; then
				TANZUCLIVER=0.11.0
				cd /tmp
				curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/vmware-tanzu/community-edition/releases/download/v${TANZUCLIVER}/tce-linux-${ARCH}-v${TANZUCLIVER}.tar.gz
				sudo -u $SUDO_USER tar zxf tce-linux-${ARCH}-v${TANZUCLIVER}.tar.gz
				cd tce-linux-${ARCH}-v${TANZUCLIVER}
				sudo -u $SUDO_USER ./install.sh
				tanzu completion bash >/etc/bash_completion.d/tanzu
				cd ${BASEPWD}
			fi
		fi
	fi
fi

if [ ${OC} -eq 1 ]; then
	if [ ! -f /usr/local/bin/oc ]; then
		mkdir /tmp/oc
		cd /tmp/oc
		OCPVER=stable-4.10
		if [ ${ARCH} = "amd64" ]; then
			OCPARCH=x86_64
		fi
		if [ ${ARCH} = "arm64" ]; then
			OCPARCH=arm64
		fi
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://mirror.openshift.com/pub/openshift-v4/${OCPARCH}/clients/ocp/${OCPVER}/openshift-client-linux.tar.gz
		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://mirror.openshift.com/pub/openshift-v4/${OCPARCH}/clients/ocp/${OCPVER}/openshift-install-linux.tar.gz
		tar xfz openshift-client-linux.tar.gz
		mv oc /usr/local/bin
		chmod -x /usr/local/bin/oc
		tar xfz openshift-install-linux.tar.gz
		mv openshift-install /usr/local/bin
		chmod +x /usr/local/bin/openshift-install
		cd ..
		rm -rf /tmp/oc
		openshift-install completion bash >/etc/bash_completion.d/openshift-install
		oc completion bash >/etc/bash_completion.d/oc
		cd ${BASEPWD}
	fi
fi

# for client installation
if [ ${CLIENT} -eq 1 ]; then
	echo -e "\e[31mk8s installation is prohibited if you install docker to this mathine. this script removes deploying k8s scripts. \e[m"
	if [ -d ../k8s-study-vanilla ]; then
		rm -rf ./2-buildk8s-lnx.sh ./3-configk8s.sh ./4-csi-storage.sh ./5-csi-vsphere.sh
		cp -rf ../k8s-study-vanilla /home/${SUDO_USER}/
		rm /home/${SUDO_USER}/k8s-study-vanilla/1-tools.sh
		chown -R ${SUDO_USER}:${SUDO_USER} /home/${SUDO_USER}/k8s-study-vanilla
	fi
fi
cd ${BASEPWD}

echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "Kubernetes tools ${KUBECTLVER} were installed in this Ubuntu."
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
	echo ""
	echo ""
	if [ ${PORTAINER} -eq 1 ]; then
		echo "portainer-ce was installed"
		echo "https://<This HOST>:9443/"
	fi
	if [ ${NERDCTL} -eq 1 ]; then
		echo "If you are using Ubuntu Desktop with X Window, plase reboot your Ubuntu desktop."
		echo "If you want to use nerdctl, once reboot, then execute containerd-rootless-setuptool.sh install in normal user."
		read -p "Press enter to continue for reboot"
		reboot
	fi
fi
chmod -x $0
ls
