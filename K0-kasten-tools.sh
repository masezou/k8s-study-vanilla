#!/usr/bin/env bash

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


# Install K10-tools
KASTENVER=4.5.4
rm -rf /usr/local/bin/k10tools
curl -OL https://github.com/kastenhq/external-tools/releases/download/${KASTENVER}/k10tools_${KASTENVER}_linux_${ARCH}.tar.gz
tar xfz k10tools_${KASTENVER}_linux_${ARCH}.tar.gz -C /usr/local/bin
rm -rf k10tools_${KASTENVER}_linux_${ARCH}.tar.gz
chmod +x /usr/local/bin/k10tools

rm -rf /usr/local/bin/k10multicluster
curl -OL https://github.com/kastenhq/external-tools/releases/download/${KASTENVER}/k10multicluster_${KASTENVER}_linux_${ARCH}.tar.gz
tar xfz k10multicluster_${KASTENVER}_linux_${ARCH}.tar.gz -C /usr/local/bin
rm -rf k10multicluster_${KASTENVER}_linux_${ARCH}.tar.gz
chmod +x /usr/local/bin/k10multicluster

KUBESTRVER=0.4.31
if [ ! -f /usr/local/bin/kubestr ]; then
rm -rf /usr/local/bin/kubestr
mkdir temp
cd temp
curl -OL https://github.com/kastenhq/kubestr/releases/download/v${KUBESTRVER}/kubestr_${KUBESTRVER}_Linux_${ARCH}.tar.gz
tar xfz kubestr_${KUBESTRVER}_Linux_${ARCH}.tar.gz
rm kubestr_${KUBESTRVER}_Linux_${ARCH}.tar.gz
mv kubestr /usr/local/bin/kubestr
chmod +x /usr/local/bin/kubestr
cd ..
rm -rf temp
fi

echo "*************************************************************************************"
echo "K10tool/K10multicluster/kubestr were installed"
echo ""

chmod -x ./K0-kasten-tools.sh
