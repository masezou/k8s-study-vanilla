#!/usr/bin/env bash
#########################################################

SC=nfs-csi
KASTENHOSTNAME=kasten-`hostname`
KASTENINGRESS=k10-`hostname`

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
bash ./get-helm-3
helm version
rm get-helm-3
helm completion bash > /etc/bash_completion.d/helm
source /etc/bash_completion.d/helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
fi
fi

#########################################################

if [ ! -f /usr/local/bin/k10tools ]; then
bash ./K0-kasten-tools.sh
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

# Install Kasten
#DNSDOMAINNAME="k8slab.internal"
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
KASTENFQDN=${KASTENHOSTNAME}.${DNSDOMAINNAME}
KASTENFQDNINGRESS=${KASTENINGRESS}.${DNSDOMAINNAME}
kubectl create ns kasten-io
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

# define NFS storage
kubectl get sc | grep nfs-csi
retval12=$?
if [ ${retval12} -eq 0 ]; then
KASTENNFSPVC=kastenbackup-pvc
cat <<EOF | kubectl apply -n kasten-io -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
   name: ${KASTENNFSPVC}
spec:
   storageClassName: nfs-csi
   accessModes:
      - ReadWriteMany
   resources:
      requests:
         storage: 20Gi
EOF
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
kubectl wait --for=condition=ready --timeout=180s -n kasten-io pod -l component=jobs
kubectl wait --for=condition=ready --timeout=180s -n kasten-io pod -l component=catalog
# configure profile/blueprint automatically
bash ./K2-kasten-storage.sh
bash ./K3-kasten-vsphere.sh
bash ./K4-kasten-blueprint.sh
bash ./K5-kasten-local-rbac.sh

sa_secret=$(kubectl get serviceaccount k10-k10 -o jsonpath="{.secrets[0].name}" --namespace kasten-io)
kubectl get secret $sa_secret --namespace kasten-io -ojsonpath="{.data.token}{'\n'}" | base64 --decode > k10-k10.token
echo "" >> k10-k10.token

EXTERNALIP=`kubectl -n kasten-io get svc gateway-ext | awk '{print $4}' | tail -n 1`
INGRESSIP=`kubectl get ingress -n kasten-io --output="jsonpath={.items[*].status.loadBalancer.ingress[*].ip}"`
KASTENFQDNURL=`kubectl -n kasten-io  get svc gateway-ext --output="jsonpath={.metadata.annotations}" | jq | grep external-dns | cut -d "\"" -f 4`
echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "Confirm wordpress kasten is running with kubectl get pods --namespace kasten-io"
echo -e "\e[32m Open your browser \e[m"
echo -e "\e[32m http://${KASTENFQDNURL}/k10/ \e[m"
echo -e "\e[32m http://${EXTERNALIP}/k10/ \e[m"
echo -e "\e[32m http://${KASTENFQDNINGRESS}/k10/ \e[m"
echo -e "\e[32m https://${KASTENFQDNINGRESS}/k10/ \e[m"
echo "then input login token"
echo -e "\e[32m cat ./k10-k10.token \e[m"
cat ./k10-k10.token
echo ""
echo "Configured profile, blueprint, rbac also."

chmod -x ./K1-kasten.sh
