#!/usr/bin/env bash

#########################################################
ONLY_PUSH=0
# Kasten  version
#KASTENVER=4.5.12
#REGISTRYHOST=192.168.16.2
#REGISTRYURL=${REGISTRYHOST}:5000
#########################################################

### Install command check ####
if type "docker" > /dev/null 2>&1
then
    echo "docker was already installed"
else
    echo "docker was not found. Please install docker and re-run"
    exit 255
fi

if [ -z ${KASTENVER} ]; then
KASTENVER=`grep KASTENVER= ./K0-kasten-tools.sh | cut -d "=" -f 2`
fi

if [ -z ${REGISTRYURL} ]; then
REGISTRYURL=`ls -1 /etc/containerd/certs.d/ | grep -v docker.io`
fi

if [ ${ONLY_PUSH} -eq 01 ]; then
mkdir -p  ~/.docker
docker run --rm -it --platform linux/amd64 gcr.io/kasten-images/k10offline:${KASTENVER} list-images
docker images ls
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock \
    --platform linux/amd64 gcr.io/kasten-images/k10offline:${KASTENVER} pull images
fi
docker run --rm -ti -v /var/run/docker.sock:/var/run/docker.sock \
    -v ${HOME}/.docker:/root/.docker \
    --platform linux/amd64 gcr.io/kasten-images/k10offline:${KASTENVER} pull images --newrepo ${REGISTRYURL}

curl -X GET http://${REGISTRYURL}/v2/_catalog |jq
