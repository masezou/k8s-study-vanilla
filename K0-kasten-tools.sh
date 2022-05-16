#!/usr/bin/env bash

#########################################################
# Kasten client version
KASTENVER=4.5.15

#########################################################
### UID Check ###
if [ ${EUID:-${UID}} != 0 ]; then
	echo "This script must be run as root"
	exit 1
else
	echo "I am root user."
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

# Install K10-tools
rm -rf /usr/local/bin/k10tools
echo "downloaing k10tools"
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/kastenhq/external-tools/releases/download/${KASTENVER}/k10tools_${KASTENVER}_linux_${ARCH}.tar.gz
tar xfz k10tools_${KASTENVER}_linux_${ARCH}.tar.gz -C /usr/local/bin
rm -rf k10tools_${KASTENVER}_linux_${ARCH}.tar.gz
chmod +x /usr/local/bin/k10tools
k10tools completion bash >/etc/bash_completion.d/k10tools

rm -rf /usr/local/bin/k10multicluster
echo "downloaing k10multicluster"
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/kastenhq/external-tools/releases/download/${KASTENVER}/k10multicluster_${KASTENVER}_linux_${ARCH}.tar.gz
tar xfz k10multicluster_${KASTENVER}_linux_${ARCH}.tar.gz -C /usr/local/bin
rm -rf k10multicluster_${KASTENVER}_linux_${ARCH}.tar.gz
chmod +x /usr/local/bin/k10multicluster
k10multicluster completion bash >/etc/bash_completion.d/k10multicluster

# Install kanctl
if type "go" >/dev/null 2>&1; then
	echo "golang was already installed"
else
	echo "golang was not installed"
	apt -y install golang
fi

if [ ! -f /usr/local/bin/kanctl ]; then
	echo "downloaing kanctl and kando"
	curl https://raw.githubusercontent.com/kanisterio/kanister/master/scripts/get.sh | bash
	kanctl completion bash >/etc/bash_completion.d/kanctl
	kando completion bash >/etc/bash_completion.d/kando
fi

# Install kubestr
KUBESTRVER=0.4.31
if [ ! -f /usr/local/bin/kubestr ]; then
	rm -rf /usr/local/bin/kubestr
	mkdir temp
	cd temp
	echo "downloaing kubestr"
	curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/kastenhq/kubestr/releases/download/v${KUBESTRVER}/kubestr_${KUBESTRVER}_$(uname -s)_${ARCH}.tar.gz
	tar xfz kubestr_${KUBESTRVER}_$(uname -s)_${ARCH}.tar.gz
	rm kubestr_${KUBESTRVER}_$(uname -s)_${ARCH}.tar.gz
	mv kubestr /usr/local/bin/kubestr
	chmod +x /usr/local/bin/kubestr
	cd ..
	rm -rf temp
fi

if [ ! -f /usr/bin/docker ]; then
	rm ./K-kasten-registry.sh
fi

echo "*************************************************************************************"
echo "K10tool/K10multicluster/kanctl/kando/kubestr were installed"
echo ""

chmod -x $0
