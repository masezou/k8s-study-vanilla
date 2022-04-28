#!/usr/bin/env bash
#########################################################

# For Install from Registry
#FORCE_ONLINE=1
#REGISTRYURL="192.168.133.2:5000"
#KASTENVER=4.5.14

# SC = csi-hostpath-sc / local-hostpath / local-path / nfs-sc / nfs-csi / vsphere-sc / example-vanilla-rwo-filesystem-sc / cstor-csi-disk
SC=nfs-csi
KASTENHOSTNAME=kasten-`kubectl get node --output="jsonpath={.items[*].metadata.labels.kubernetes\.io\/hostname}"`
KASTENINGRESS=k10-`kubectl get node --output="jsonpath={.items[*].metadata.labels.kubernetes\.io\/hostname}"`

STORAGECONFIG=1
VSPHERECONFIG=1
BLUEPRINT=1
RBAC=1
MULTICLUSTER=1

#########################################################

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
if [ ! -f /usr/local/bin/helm ]; then
curl -s -O https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
sudo bash ./get-helm-3
helm version
rm get-helm-3
sudo helm completion bash > /etc/bash_completion.d/helm
source /etc/bash_completion.d/helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
fi
fi

#########################################################

if [ ! -f /usr/local/bin/k10tools ]; then
bash ./K0-kasten-tools.sh
fi

if [ -z ${REGISTRYURL} ]; then
REGISTRYHOST=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_host}'`
REIGSTRYPORT=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_port}'`
REGISTRYURL=${REGISTRYHOST}:${REIGSTRYPORT}
curl -s  -X GET http://${REGISTRYURL}/v2/_catalog |grep kanister
retvalcheck=$?
if [ ${retvalcheck} -eq 0 ]; then
  ONLINE=0
  else
  ONLINE=1
fi
if [ ! -z ${FORCE_ONLINE} ] ; then
ONLINE=1
fi
fi

# Pre-req Kasten
helm repo add kasten https://charts.kasten.io/
helm repo update

kubectl get volumesnapshotclass | grep csi-hostpath-snapclass
retval1=$?
if [ ${retval1} -eq 0 ]; then
kubectl annotate volumesnapshotclass csi-hostpath-snapclass \
    k10.kasten.io/is-snapshot-class=true
fi

kubectl get volumesnapshotclass | grep csi-rbdplugin-snapclass
retval2=$?
if [ ${retval2} -eq 0 ]; then
kubectl annotate volumesnapshotclass csi-rbdplugin-snapclass \
    k10.kasten.io/is-snapshot-class=true
fi

kubectl get volumesnapshotclass | grep longhorn
retval4=$?
if [ ${retval4} -eq 0 ]; then
kubectl annotate volumesnapshotclass longhorn \
    k10.kasten.io/is-snapshot-class=true
fi

kubectl get volumesnapshotclass | grep csi-cstor-snapshotclass
retval7=$?
if [ ${retval7} -eq 0 ]; then
kubectl annotate volumesnapshotclass csi-cstor-snapshotclass \
    k10.kasten.io/is-snapshot-class=true
fi
k10tools primer

# Checking Storage Class availability
SCDEFAULT=`kubectl get sc | grep default | cut -d " " -f1`
kubectl get sc | grep ${SC}
retvalsc=$?
if [ ${retvalsc} -ne 0 ]; then
echo -e "\e[31m Switching to default storage class \e[m"
SC=${SCDEFAULT}
echo ${SC}
fi

# Install Kasten
kubectl create ns kasten-io

# k3s check
kubectl get node | grep k3s
retvalk3s=$?
if [ ${retvalk3s} -eq 0 ]; then
echo "It is k3s"
helm install k10 kasten/k10 --namespace=kasten-io \
--set global.persistence.size=40G \
--set global.persistence.storageClass=local-path \
--set grafana.enabled=true \
--set auth.tokenAuth.enabled=true \
--set injectKanisterSidecar.enabled=true \
--set-string injectKanisterSidecar.namespaceSelector.matchLabels.k10/injectKanisterSidecar=true 
else
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
KASTENFQDN=${KASTENHOSTNAME}.${DNSDOMAINNAME}
KASTENFQDNINGRESS=${KASTENINGRESS}.${DNSDOMAINNAME}
if [ ${ONLINE} -eq 1 ]; then
helm install k10 kasten/k10 --namespace=kasten-io \
--set global.persistence.size=40G \
--set global.persistence.storageClass=${SC} \
--set grafana.enabled=true \
--set vmWare.taskTimeoutMin=200 \
--set auth.tokenAuth.enabled=true \
--set externalGateway.create=true \
--set externalGateway.fqdn.name=${KASTENFQDN} \
--set externalGateway.fqdn.type=external-dns \
--set gateway.insecureDisableSSLVerify=true \
--set ingress.create=true \
--set ingress.class=nginx \
--set ingress.host=${KASTENFQDNINGRESS} \
--set injectKanisterSidecar.enabled=true \
--set-string injectKanisterSidecar.namespaceSelector.matchLabels.k10/injectKanisterSidecar=true 
else
if [ -z ${REGISTRYURL} ]; then
#LOCALIPADDR=`kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'`
#REGISTRYURL="${LOCALIPADDR}:5000"
ls -1 /etc/containerd/certs.d/ | grep -v docker.io
retchk=$?
if [ ${retchk} -ne 0 ]; then
echo -e "\e[31m Registry is not configured on this host. Exit. \e[m"
exit 255
fi
REGISTRYURL=`ls -1 /etc/containerd/certs.d/ | grep -v docker.io`
fi
if [ -z ${KASTENVER} ]; then
KASTENVER=`grep KASTENVER= ./K0-kasten-tools.sh | cut -d "=" -f2`
fi
helm repo add kasten https://charts.kasten.io/
helm repo update && \
    helm fetch kasten/k10
ls k10-${KASTENVER}.tgz
kubectl create ns kasten-io
helm install k10 k10-${KASTENVER}.tgz --namespace kasten-io \
--set global.airgapped.repository=${REGISTRYURL} \
--set global.persistence.size=40G \
--set global.persistence.storageClass=${SC} \
--set grafana.enabled=true \
--set vmWare.taskTimeoutMin=200 \
--set auth.tokenAuth.enabled=true \
--set externalGateway.create=true \
--set externalGateway.fqdn.name=${KASTENFQDN} \
--set externalGateway.fqdn.type=external-dns \
--set gateway.insecureDisableSSLVerify=true \
--set ingress.create=true \
--set ingress.class=nginx \
--set ingress.host=${KASTENFQDNINGRESS} \
--set injectKanisterSidecar.enabled=true \
--set-string injectKanisterSidecar.namespaceSelector.matchLabels.k10/injectKanisterSidecar=true
fi
fi

sleep 2
kubectl get deployment -n kasten-io gateway
echo "Deploying Kasten Please wait...."
sleep 60
while [ "$(kubectl get deployment -n kasten-io gateway --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
        echo "Deploying Kasten Please wait...."
        kubectl get deployment -n kasten-io gateway
        sleep 30
        kubectl get deployment -n kasten-io gateway
done
kubectl wait --for=condition=ready --timeout=360s -n kasten-io pod -l component=jobs
kubectl wait --for=condition=ready --timeout=360s -n kasten-io pod -l component=catalog
# configure profile/blueprint automatically
if [ ${STORAGECONFIG} -eq 1 ]; then
bash ./K2-kasten-storage.sh
fi
if [ ${VSPHERECONFIG} -eq 1 ]; then
bash ./K3-kasten-vsphere.sh
fi
if [ ${BLUEPRINT} -eq 1 ]; then
bash ./K4-kasten-blueprint.sh
fi
if [ ${RBAC} -eq 1 ]; then
bash ./K5-kasten-local-rbac.sh
fi
if [ ${MULTICLUSTER} -eq 1 ]; then
bash ./K6-Kasten-multicluster.sh
fi
sa_secret=$(kubectl get serviceaccount k10-k10 -o jsonpath="{.secrets[0].name}" --namespace kasten-io)
kubectl get secret $sa_secret --namespace kasten-io -ojsonpath="{.data.token}{'\n'}" | base64 --decode > k10-k10.token
echo "" >> k10-k10.token

if [ ${retvalk3s} -ne 0 ]; then
EXTERNALIP=`kubectl -n kasten-io get svc gateway-ext | awk '{print $4}' | tail -n 1`
INGRESSIP=`kubectl get ingress -n kasten-io --output="jsonpath={.items[*].status.loadBalancer.ingress[*].ip}"`
KASTENFQDNURL=`kubectl -n kasten-io  get svc gateway-ext --output="jsonpath={.metadata.annotations}" | jq | grep external-dns | cut -d "\"" -f 4`

sleep 10
host ${KASTENFQDNURL}
retvaldns1=$?
host ${KASTENFQDNINGRESS}
retvaldns2=$?
fi
echo ""
echo "*************************************************************************************"
if [ -z ${ONLINE} ]; then
kubectl images -n kasten-io
fi
echo "Next Step"
echo "Confirm wordpress kasten is running with kubectl get pods --namespace kasten-io"
echo -e "\e[32m Open your browser \e[m"
echo -e "\e[32m http://${EXTERNALIP}/k10/ \e[m"
if [ ${retvaldns1} -eq 0 ]; then
echo -e "\e[32m http://${KASTENFQDNURL}/k10/ \e[m"
fi
if [ ${retvaldns2} -eq 0 ]; then
echo -e "\e[32m http://${KASTENFQDNINGRESS}/k10/ \e[m"
echo -e "\e[32m https://${KASTENFQDNINGRESS}/k10/ \e[m"
fi
echo "then input login token"
echo -e "\e[32m cat ./k10-k10.token \e[m"
cat ./k10-k10.token
echo ""
kubectl top nodes
echo "Configured profile, blueprint, rbac also."

chmod -x $0
