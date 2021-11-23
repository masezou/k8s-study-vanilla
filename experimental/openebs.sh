#!/usr/bin/env bash

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
WORKERNAME=`hostname`
BLOCKDEVICENAME=`kubectl get bd -n openebs | grep `hostname` | cut -d " " -f1`
cat <<EOF | kubectl create -f -
apiVersion: cstor.openebs.io/v1
kind: CStorPoolCluster
metadata:
 name: cstor-disk-pool
 namespace: openebs
spec:
 pools:
   - nodeSelector:
       kubernetes.io/hostname: "${WORKERNAME}"
     dataRaidGroups:
       - blockDevices:
           - blockDeviceName: "${BLOCKDEVICENAME}
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
