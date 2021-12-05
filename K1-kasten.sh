#!/usr/bin/env bash

SC=nfs-csi

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
kubectl create ns kasten-io
helm install k10 kasten/k10 --namespace=kasten-io \
--set global.persistence.size=40G \
--set global.persistence.storageClass=${SC} \
--set grafana.enabled=true \
--set vmWare.taskTimeoutMin=200 \
--set auth.tokenAuth.enabled=true \
--set externalGateway.create=true \
--set gateway.insecureDisableSSLVerify=true \
--set ingress.create=true \
--set ingress.class=nginx \
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
echo "Deploying Kasten Please wait...."
sleep 60
while [ "$(kubectl get deployment -n kasten-io gateway --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
        echo "Deploying Kasten Please wait...."
        sleep 30
done
kubectl wait --for=condition=ready --timeout=180s -n kasten-io pod -l component=jobs
kubectl wait --for=condition=ready --timeout=180s -n kasten-io pod -l component=catalog
# configure profile/blueprint automatically
./K2-kasten-storage.sh
./K3-kasten-vsphere.sh
./K4-kasten-blueprint.sh
./K5-kasten-local-rbac.sh

sa_secret=$(kubectl get serviceaccount k10-k10 -o jsonpath="{.secrets[0].name}" --namespace kasten-io)
kubectl get secret $sa_secret --namespace kasten-io -ojsonpath="{.data.token}{'\n'}" | base64 --decode > k10-k10.token
echo "" >> k10-k10.token

EXTERNALIP=`kubectl -n kasten-io get svc gateway-ext | awk '{print $4}' | tail -n 1`
echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "Confirm wordpress kasten is running with kubectl get pods --namespace kasten-io"
echo -e "\e[32m Open your browser http://${EXTERNALIP}/k10/ \e[m"
echo "then input login token"
echo -e "\e[32m cat ./k10-k10.token \e[m"
cat ./k10-k10.token
echo ""
echo "Configured profile, blueprint, rbac also."

chmod -x ./K1-kasten.sh
