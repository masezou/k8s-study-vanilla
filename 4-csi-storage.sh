#!/usr/bin/env bash
#########################################################

# Specify NFS storage location path
NFSPATH=/disk/nfs_csi
NFSSUBPATH=/disk/nfs_sub
OPENEBS=1
#FORCE_LOCALIP=192.168.16.2

# Experimental

SYNOLOGY=0

SYNOLOGYHOST="YOUR_SYNOLOGY_HOST"
SYNOLOGYPORT="5001"
SYNOLOGYHTTPS="true"
SYNOLOGYUSERNAME="YOUR_SYNOLOGY_USER"
SYNOLOGYPASSWORD="YOUR_SYNOLOGY_PASSWORD"

#########################################################
### UID Check ###
if [ ${EUID:-${UID}} != 0 ]; then
    echo "This script must be run as root"
    exit 1
else
    echo "I am root user."
fi

# HOSTNAME check
ping -c 3 `hostname`
retvalping=$?
if [ ${retvalping} -ne 0 ]; then
echo -e "\e[31m HOSTNAME was not configured correctly. \e[m"
exit 255
fi

### Distribution Check ###
UBUNTUVER=`grep DISTRIB_RELEASE /etc/lsb-release | cut -d "=" -f2`
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

### Install command check ####
if type "kubectl" > /dev/null 2>&1
then
    echo "kubectl was already installed"
else
    echo "kubectl was not found. Please install kubectl and re-run"
    exit 255
fi

### Cluster check ####
kubectl get pod 
retavalcluser=$?
if [ ${retavalcluser} -ne 0 ]; then
echo -e "\e[31m Kubernetes cluster is not found. \e[m"
exit 255
fi

#### LOCALIP (from kubectl) #########
if [ -z ${FORCE_LOCALIP} ]; then
LOCALIPADDR=`kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'`
else
LOCALIPADDR=${FORCE_LOCALIP}
fi
if [ -z ${LOCALIPADDR} ]; then
echo -e "\e[31m Local IP address setting was failed, please set FORCE_LOCALIP and re-run.  \e[m"
exit 255
else
echo ${LOCALIPADDR}
fi

BASEPWD=`pwd`
source /etc/profile

kubectl get node | grep "NotReady"
retvalstatus=$?
if [ ${retvalstatus} -eq 0 ]; then
echo -e "\e[31m CNI is not configured. exit. \e[m"
exit 255
fi

kubectl get sc | grep openebs
retvalopenebs=$?
if [ ${retvalopenebs} -ne 0 ]; then
if [ ${OPENEBS} -eq 1 ]; then
# Device /dev/sdb check
df | grep sdb
retvalmount=$?
if [ ${retvalmount} -ne 0 ]; then
pvscan | grep sdb
retvallvm=$?
if [ ${retvallvm} -ne 0 ]; then
if [  -b /dev/sdb ]; then
echo "Initilize /dev/sdb....."
sgdisk -Z /dev/sdb
INITDISK=1
fi
fi
fi
fi
fi

# Device /dev/sdc check
df | grep sdc
retvalmount=$?
if [ ${retvalmount} -ne 0 ]; then
pvscan | grep sdc
retvallvm=$?
if [ ${retvallvm} -ne 0 ]; then
if [  -b /dev/sdc ]; then
echo "Initilize /dev/sdc....."
sgdisk -Z /dev/sdc
INITDISK=1
fi
fi
fi
if [ -z ${INITDISK} ]; then
OPENEBS=0
fi

# Install OpenEBS
if [ ${retvalopenebs} -ne 0 ]; then
if [ ${OPENEBS} -ne 0 ]; then
apt install -y open-iscsi
systemctl enable iscsid && systemctl start iscsid
mkdir -p /var/openebs/local
kubectl -n kube-system create serviceaccount tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
for WORKERNODES in `kubectl get node |grep -v NAME| grep worker | cut -d " " -f 1`; do
echo ${WORKERNODES}
kubectl label nodes ${WORKERNODES} node=openebs
done
helm repo add openebs https://openebs.github.io/charts
helm repo update
helm install openebs --namespace openebs openebs/openebs --create-namespace \
--set cstor.enabled=true 
sleep 2
kubectl -n openebs get pod openebs-cstor-csi-controller-0
echo "Initial wait 30s"
sleep 30
while [ "$(kubectl -n openebs get pod openebs-cstor-csi-controller-0 --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f3)" != "True" ]; do
        echo "Deploying OpenEBS Please wait...."
        kubectl -n openebs get pod openebs-cstor-csi-controller-0
        sleep 30
done
        kubectl -n openebs get pod openebs-cstor-csi-controller-0
kubectl -n openebs wait pod  -l component=openebs-cstor-csi-node --for condition=Ready
WORKERNODES=`kubectl get bd -n openebs | grep -i Unclaimed | cut -d " " -f4`
BLOCKDEVICENAME=`kubectl get bd -n openebs | grep -i Unclaimed | cut -d " " -f1`
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
cat <<EOF | kubectl create -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-hostpath
  annotations:
    openebs.io/cas-type: local
    cas.openebs.io/config: |
      - name: StorageType
        value: hostpath
      - name: BasePath
        value: /var/local-hostpath
provisioner: openebs.io/local
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF
kubectl patch storageclass cstor-csi-disk -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl -n openebs wait pod  -l app=cstor-pool --for condition=Ready
fi
fi

if [ ${OPENEBS} -ne 1 ]; then
kubectl get sc | grep local-path
retvallocalpath=$?
if [ ${retvallocalpath} -ne 0 ]; then
# Rancher local driver (Not CSI Storage)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
fi
SNAPSHOTTER_VERSION=5.0.1
# Apply VolumeSnapshot CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
# Create Snapshot Controller
kubectl -n kube-system apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl -n kube-system apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

##Install the CSI Hostpath Driver
kubectl get sc | grep csi-hostpath-sc
retvalcsihostpathsc=$?
if [ ${retvalcsihostpathsc} -ne 0 ]; then
 
# kubernetes version check
kubectl get node -o wide|grep v1.19  > /dev/null 2>&1 && KUBEVER=1.19
kubectl get node -o wide|grep v1.20  > /dev/null 2>&1 && KUBEVER=1.20
kubectl get node -o wide|grep v1.21  > /dev/null 2>&1 && KUBEVER=1.21
kubectl get node -o wide|grep v1.22  > /dev/null 2>&1 && KUBEVER=1.22
kubectl get node -o wide|grep v1.23  > /dev/null 2>&1 && KUBEVER=1.23

if [ ${KUBEVER}=1.19 ]; then
if [ -z ${CSIHOSTPATHDONE} ]; then
CSIHOSTPATHVER=1.7.3
git clone https://github.com/kubernetes-csi/csi-driver-host-path -b v${CSIHOSTPATHVER} --depth 1
cd csi-driver-host-path
./deploy/kubernetes-${KUBEVER}/deploy.sh
CSIHOSTPATHDONE=1
fi
fi

if [ ${KUBEVER}=1.20 ]; then
if [ -z ${CSIHOSTPATHDONE} ]; then
CSIHOSTPATHVER=1.7.3
git clone https://github.com/kubernetes-csi/csi-driver-host-path -b v${CSIHOSTPATHVER} --depth 1
cd csi-driver-host-path
./deploy/kubernetes-${KUBEVER}/deploy.sh
CSIHOSTPATHDONE=1
fi
fi

if [ ${KUBEVER}=1.21 ]; then
if [ -z ${CSIHOSTPATHDONE} ]; then
git clone https://github.com/kubernetes-csi/csi-driver-host-path --depth 1
cd csi-driver-host-path
./deploy/kubernetes-${KUBEVER}/deploy.sh
CSIHOSTPATHDONE=1
fi
fi

if [ ${KUBEVER}=1.22 ]; then
if [ -z ${CSIHOSTPATHDONE} ]; then
git clone https://github.com/kubernetes-csi/csi-driver-host-path --depth 1
cd csi-driver-host-path
./deploy/kubernetes-${KUBEVER}/deploy.sh
CSIHOSTPATHDONE=1
fi
fi

if [ ${KUBEVER}=1.23 ]; then
if [ -z ${CSIHOSTPATHDONE} ]; then
echo "${KUBEVER} is not supported yet."
CSIHOSTPATHDONE=0
fi
fi

if [ ${CSIHOSTPATHDONE} -eq 1 ]; then
kubectl apply -f ./examples/csi-storageclass.yaml
kubectl patch storageclass csi-hostpath-sc \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
cd ..
rm -rf csi-driver-host-path
fi

# Permission fix
chmod -R 1777 /var/lib/docker/volumes/
fi
fi

##Install NFS-CSI driver
kubectl get sc | grep nfs
retvalnfssc=$?
if [ ${retvalnfssc} -ne 0 ]; then
apt -y install nfs-kernel-server
apt -y autoremove
apt clean
mkdir -p ${NFSPATH}
chmod -R 1777 ${NFSPATH}
mkdir -p ${NFSSUBPATH}
chmod -R 1777 ${NFSSUBPATH}
cat << EOF >> /etc/exports
${NFSPATH} 192.168.0.0/16(rw,async,no_root_squash)
${NFSPATH} 172.16.0.0/12(rw,async,no_root_squash)
${NFSPATH} 10.0.0.0/8(rw,async,no_root_squash)
${NFSPATH} 127.0.0.1/8(rw,async,no_root_squash)
${NFSSUBPATH} 192.168.0.0/16(rw,async,no_root_squash)
${NFSSUBPATH} 172.16.0.0/12(rw,async,no_root_squash)
${NFSSUBPATH} 10.0.0.0/8(rw,async,no_root_squash)
${NFSSUBPATH} 127.0.0.1/8(rw,async,no_root_squash)
EOF
systemctl restart nfs-server
systemctl enable nfs-server
showmount -e

# Install NFS-CSI driver for single node
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/rbac-csi-nfs-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/csi-nfs-driverinfo.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/csi-nfs-controller.yaml
kubectl -n kube-system patch deployment csi-nfs-controller -p '{"spec":{"replicas": 1}}'
sleep 2
kubectl -n kube-system get deployments.apps csi-nfs-controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/csi-nfs-node.yaml
while [ "$(kubectl -n kube-system get deployments.apps csi-nfs-controller --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
       echo "Deploying CSI-NFS controller Please wait...."
    kubectl -n kube-system get deployments.apps csi-nfs-controller
       sleep 30
done
    kubectl -n kube-system get deployments.apps csi-nfs-controller
kubectl -n kube-system wait pod -l app=csi-nfs-node --for condition=Ready --timeout 180s

curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/example/storageclass-nfs.yaml
sed -i -e "s/nfs-server.default.svc.cluster.local/${LOCALIPADDR}/g" storageclass-nfs.yaml
sed -i -e "s@share: /@share: ${NFSPATH}@g" storageclass-nfs.yaml
kubectl create -f storageclass-nfs.yaml
kubectl create secret generic mount-options --from-literal mountOptions="nfsvers=3,hard"
rm -rf storageclass-nfs.yaml
kubectl patch storageclass nfs-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl delete CSIDriver nfs.csi.k8s.io
cat <<EOF | kubectl create -f -
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: nfs.csi.k8s.io
spec:
  attachRequired: false
  volumeLifecycleModes:
    - Persistent
  fsGroupPolicy: File
EOF

# Install NFS-SUB
kubectl create namespace nfs-subdir
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner -n nfs-subdir \
    --set nfs.server=${LOCALIPADDR} \
    --set nfs.path=${NFSSUBPATH} \
    --set storageClass.name=nfs-sc
fi

# Install Synology CSI (Experimental)
if [ ${SYNOLOGY} -eq 1 ]; then
git clone https://github.com/kubernetes-csi/external-snapshotter
cd external-snapshotter
kubectl kustomize client/config/crd | kubectl create -f -
kubectl -n kube-system kustomize deploy/kubernetes/snapshot-controller | kubectl create -f -
cd ..
apt -y install make golang-go
git clone --depth 1 git@github.com:SynologyOpenSource/synology-csi.git
cd synology-csi
cat << EOF > config/client-info.yml
---
clients:
  - host: ${SYNOLOGYHOST}
    port: ${SYNOLOGYPORT}
    https: ${SYNOLOGYHTTPS}
    username: ${SYNOLOGYUSERNAME}
    password: ${SYNOLOGYPASSWORD}
EOF

./scripts/deploy.sh install --all
cd ..
kubectl get pods -n synology-csi
kubectl apply -f deploy/kubernetes/v1.19/storage-class.yml
kubectl apply -f deploy/kubernetes/v1.19/snapshotter/volume-snapshot-class.yml
kubectl -n synology-csi wait pod  -l app=synology-csi-controller --for condition=Ready
kubectl -n synology-csi wait pod  -l app=synology-csi-node --for condition=Ready
kubectl -n synology-csi wait pod  -l app=synology-csi-snapshotter --for condition=Ready
fi

kubectl -n openebs wait pod  -l app=cstor-pool --for condition=Ready

echo ""
echo "*************************************************************************************"
echo "CSI storage was created"
echo "kubectl get sc"
kubectl get sc
echo ""
echo "kubernetes deployment without vSphere CSI driver was successfully. The environment will be functional."
echo ""
echo -e "\e[32m If you want to use vSphere CSI Driver on ESX/vCenter environment, run ./5-csi-vsphere.sh \e[m"
echo ""

cd ${BASEPWD}
chmod -x $0
