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

### Install command check ####
if type "kubectl" > /dev/null 2>&1
then
    echo "kubectl was already installed"
else
    echo "kubectl was not found. Please install kubectl and re-run"
    exit 255
fi

if type "helm" > /dev/null 2>&1
then
    echo "helm was already installed"
else
    echo "helm was not found. Please install helm and re-run"
    exit 255
fi

apt install -y open-iscsi
systemctl enable iscsid && systemctl start iscsid
kubectl -n kube-system create serviceaccount tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
for WORKERNODES in `kubectl get node |grep -v NAME| grep worker | cut -d " " -f 1`; do
echo ${WORKERNODES}
kubectl label nodes ${WORKERNODES} node=openebs
done
helm repo add openebs https://openebs.github.io/charts
helm repo update
helm install openebs --namespace openebs openebs/openebs --create-namespace --set cstor.enabled=true
echo "Initial wait 30s"
sleep 30
while [ "$(kubectl -n openebs get pod openebs-cstor-csi-controller-0 --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f3)" != "True" ]; do
        echo "Deploying OpenEBS Please wait...."
   kubectl -n openebs get pod
        sleep 30
done
#WORKERNAME=`hostname`
BLOCKDEVICENAME=`kubectl get bd -n openebs | grep ${WORKERNODES}| cut -d " " -f1`
cat <<EOF | kubectl create -f -
apiVersion: cstor.openebs.io/v1
kind: CStorPoolCluster
metadata:
 name: cstor-disk-pool
 namespace: openebs
spec:
 pools:
   - nodeSelector:
       kubernetes.io/hostname: "${WORKERNODES}"
     dataRaidGroups:
       - blockDevices:
           - blockDeviceName: "${BLOCKDEVICENAME}"
     poolConfig:
       dataRaidGroupType: "stripe"
EOF
cat <<EOF | kubectl create -f -
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: cstor-csi-disk
provisioner: cstor.csi.openebs.io
allowVolumeExpansion: true
parameters:
  cas-type: cstor
  # cstorPoolCluster should have the name of the CSPC
  cstorPoolCluster: cstor-disk-pool
  # replicaCount should be <= no. of CSPI created in the selected CSPC
  replicaCount: "1"
EOF

chmod +x openebs.sh

