#!/usr/bin/env bash
#########################################################
# Pre-requirement
# vCenter needs to be 6.7U3 above and to be set DISKUUID.
#########################################################
# Edit this section

#For vSphere CSI driver
VSPHEREUSERNAME="administrator@vsphere.local"
VSPHEREPASSWORD="YOUR_VCENTER_PASSWORD"
VSPHERESERVER="YOUR_VCENTER_FQDN"
VSPHERESERVERIP="YOUR_VCENTER_IP"
VSPPHEREDATASTORE="YOUR_DATASTORE"

#########################################################
VSPHERECSI=2.3.0

if [ ${EUID:-${UID}} != 0 ]; then
    echo "This script must be run as root"
    exit 1
else
    echo "I am root user."
fi

### Install command check ####
if type "kubeadm" > /dev/null 2>&1
then
    echo "kubeadm was already installed"
else
    echo "kubeadm was not found. It seems this environment is not supported"
    exit 255
fi

# Forget trap!
if [ ${VSPHERESERVER} = "YOUR_VCENTER_FQDN" ]; then
echo -e "\e[31m You haven't set environment value.  \e[m"
echo -e "\e[31m please set vCenter setting in this script.  \e[m"
exit 255
fi

BASEPWD=`pwd`

# vSphere environment check
lspci -tv | grep VMware
retavalvm=$?
if [ ${retavalvm} -ne 0 ];then
   echo "This is not VMware environment. exit."
   chmod -x ./5-csi-vsphere.sh
   exit 0
else
apt -y install open-vm-tools
apt clean
fi

# Cluster check ####
kubectl get pod 
retavalcluser=$?
if [ ${retavalcluser} -ne 0 ]; then
echo -e "\e[31m Kubernetes cluster is not found. \e[m"
exit 255
fi

kubectl get node | grep "NotReady"
retvalstatus=$?
if [ ${retvalstatus} -eq 0 ]; then
echo -e "\e[31m CNI is not configured. exit. \e[m"
exit 255
fi

# DISKUUID check
ls /dev/disk/by-id/scsi-*
retvaluuid=$?
if [ ${retvaluuid} -ne 0 ];then
echo -e "\e[31m It seemed DISKUUID is not set. Please set DISKUUID then re-try. \e[m"
exit 255
fi

# Setup Govc
cat << EOF > ~/govc-vcenter.sh
export GOVC_INSECURE=1 # Don't verify SSL certs on vCenter
export GOVC_URL=${VSPHERESERVER} # vCenter IP/FQDN
export GOVC_USERNAME=${VSPHEREUSERNAME} # vCenter username
export GOVC_PASSWORD=${VSPHEREPASSWORD} # vCenter password
export GOVC_DATASTORE=${VSPPHEREDATASTORE} # Default datastore to deploy to
export GOVC_NETWORK="${VSPPHERENETWORK}" # Default network to deploy to
#export GOVC_RESOURCE_POOL='*/Resources' # Default resource pool to deploy to
# check govc find / -type p
export GOVC_RESOURCE_POOL='${VSPHERERESOURCEPOOL}' # Default resource pool to deploy to
EOF
if [ ! -f /usr/local/bin/govc ]; then
GOVCVER=v0.27.2
curl -OL https://github.com/vmware/govmomi/releases/download/${GOVCVER}/govc_Linux_x86_64.tar.gz
mkdir govcbin
tar xfz govc_Linux_x86_64.tar.gz -C govcbin
rm govc_Linux_x86_64.tar.gz
mv govcbin/govc /usr/local/bin
rm -rf govcbin
curl -OL https://raw.githubusercontent.com/vmware/govmomi/master/scripts/govc_bash_completion
mv govc_bash_completion /etc/bash_completion.d/
fi
source ~/govc-vcenter.sh

# Verify vCenter connectivity
govc datacenter.info
retvalvcconnect=$?
if [ ${retvalvcconnect} -ne 0 ]; then
echo -e "\e[31m It seemed ${VSPHERESERVER} was not able to connect from tis node. Please check vCenter connectivity and re-run.  \e[m"
rm ~/govc-vcenter.sh
exit 255
fi

# Configure vsphere-cloud-controller-manager
cat << EOF >  /etc/kubernetes/vsphere.conf
# Global properties in this section will be used for all specified vCenters unless overriden in VirtualCenter section.
global:
  port: 443
  # set insecureFlag to true if the vCenter uses a self-signed cert
  insecureFlag: true
  # settings for using k8s secret
  secretName: cpi-global-secret
  secretNamespace: kube-system

# vcenter section
vcenter:
  tenant-engineering:
    server: ${VSPHERESERVERIP}
    datacenters:
      - Datacenter
#    secretName: cpi-secret
#    secretNamespace: kube-system

# labels for regions and zones
#labels:
#  region: k8s-region
#  zone: k8s-zone
EOF
cd /etc/kubernetes
kubectl create configmap cloud-config --from-file=vsphere.conf --namespace=kube-system
kubectl get cm cloud-config --namespace=kube-system
cd

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cpi-global-secret
  namespace: kube-system
stringData:
  ${VSPHERESERVERIP}.username: "${VSPHEREUSERNAME}"
  ${VSPHERESERVERIP}.password: "${VSPHEREPASSWORD}"
EOF
kubectl get secret cpi-global-secret --namespace=kube-system

#########################################################################################
# Set your all node.(Master/Worker)
for NODES in `kubectl get node |grep -v NAME|  cut -d " " -f 1`; do
    echo ${NODES}
    kubectl taint nodes ${NODES} node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule
done

kubectl describe nodes | egrep "Taints:|Name:"
## Check taint is ON

kubectl apply -f https://raw.githubusercontent.com/kubernetes/cloud-provider-vsphere/master/manifests/controller-manager/cloud-controller-manager-roles.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/cloud-provider-vsphere/master/manifests/controller-manager/cloud-controller-manager-role-bindings.yaml
kubectl apply -f https://github.com/kubernetes/cloud-provider-vsphere/raw/master/manifests/controller-manager/vsphere-cloud-controller-manager-ds.yaml
kubectl get pods --namespace=kube-system| grep vsphere-cloud-controller-manager
kubectl describe nodes | egrep "Taints:|Name:"
## Check taint has been wipeout

kubectl describe nodes | grep "Provider"
## Check Provider shows

rm /etc/kubernetes/vsphere.conf

#########################################################################################
# Set your master node only.
for MASTERNODES in `kubectl get node |grep -v NAME| grep master| cut -d " " -f 1`; do
echo ${MASTERNODES}
kubectl taint nodes ${MASTERNODES} node-role.kubernetes.io/master=:NoSchedule
done
#########################################################################################
kubectl describe nodes | egrep "Taints:|Name:"
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v${VSPHERECSI}/manifests/vanilla/namespace.yaml

# Install CSI Driver
# https://vsphere-csi-driver.sigs.k8s.io/driver-deployment/installation.html
cat << EOF> /etc/kubernetes/csi-vsphere.conf
[Global]
cluster-id = "cluster-id"
cluster-distribution = "Ubuntu"
[VirtualCenter "${VSPHERESERVERIP}"]
insecure-flag = "true"
user = "${VSPHEREUSERNAME}"
password = "${VSPHEREPASSWORD}"
port = "443"
datacenters = "Datacenter"
EOF

cd /etc/kubernetes
kubectl create secret generic vsphere-config-secret --from-file=csi-vsphere.conf --namespace=vmware-system-csi
rm /etc/kubernetes/csi-vsphere.conf
kubectl get secret vsphere-config-secret --namespace=vmware-system-csi
cd

curl -OL https://raw.githubusercontent.com/kubernetes-sigs/vsphere-csi-driver/v${VSPHERECSI}/manifests/vanilla/vsphere-csi-driver.yaml
# v2.4.0 fix
if [ ${VSPHERECSI}="2.4.0" ]; then 
sed -i -e "s/replicas: 3/replicas: 1/g" vsphere-csi-driver.yaml
fi
kubectl apply -f vsphere-csi-driver.yaml
rm -rf vsphere-csi-driver.yaml

sleep 2
kubectl -n vmware-system-csi get deployments.apps vsphere-csi-controller
while [ "$(kubectl -n vmware-system-csi get deployments.apps vsphere-csi-controller --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
     echo "Deploying Ingress-nginx controller Please wait...."
     kubectl -n vmware-system-csi get deployments.apps vsphere-csi-controller
     sleep 30
done
     kubectl -n vmware-system-csi get deployments.apps vsphere-csi-controller
kubectl  -n vmware-system-csi wait all -l app=vsphere-csi-node --for condition=Ready --timeout 180s

retvalvspherecsinode=$?
if [ ${retvalvspherecsinode} -ne 0 ]; then
echo -e "\e[31m It seemed there is wrong configuration or some malfunction happened. \e[m"
exit 255
fi

# Add Tag to vCenter
govc tags.ls | grep k8s-zone
retval2=$?
if [ ${retval2} -ne 0 ]; then
govc tags.category.create -d "Kubernetes zone" k8s-zone
govc tags.create -d "Kubernetes Zone" -c k8s-zone k8s-zone
govc tags.attach k8s-zone /Datacenter
fi

# Assign datastore
govc tags.attach -c k8s-zone k8s-zone /Datacenter/datastore/${VSPPHEREDATASTORE}
retvalds=$?
if [ ${retvalds} -ne 0 ]; then
echo -e "\e[31m It seemed ${VSPPHEREDATASTORE} was wrong. Please set Datastore tag manually in vCenter.  \e[m"
fi

# Create Storage policy
govc storage.policy.ls | grep k8s-policy
retval4=$?
if [ ${retval4} -ne 0 ]; then
  govc storage.policy.create -category k8s-zone -tag k8s-zone k8s-policy
fi

cat <<EOF | kubectl apply -f -
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: vsphere-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.vmware.com
parameters:
  storagepolicyname: "k8s-policy"
  fstype: ext4
EOF

kubectl taint nodes --all node-role.kubernetes.io/master-
kubectl label node `hostname` node-role.kubernetes.io/worker=worker

kubectl patch storageclass csi-hostpath-sc \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass cstor-csi-disk \
    -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

echo ""
echo "*************************************************************************************"
echo -e "\e[32m vSphere CSI Driver installation and Storage Class creation is done. \e[m"
echo ""
echo "kubectl get sc"
kubectl get sc
echo ""

cd ${BASEPWD}
if [ -z $SUDO_USER ]; then
  echo "there is no sudo login"
else
head -n 16 5-csi-vsphere.sh > vsphere-env
mkdir -p /home/${SUDO_USER}/k8s-study-vanilla/
cp vsphere-env /home/${SUDO_USER}/k8s-study-vanilla/vsphere-env
chmod -x  /home/${SUDO_USER}/k8s-study-vanilla/vsphere-env
fi
chmod -x ./5-csi-vsphere.sh
