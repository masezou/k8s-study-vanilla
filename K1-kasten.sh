#!/usr/bin/env bash


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

#########################################################


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
--set global.persistence.storageClass=nfs-csi \
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

while [ "$(kubectl get deployment -n kasten-io gateway --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
        echo "Deploying Kasten Please wait...."
        sleep 30
done

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
echo "If you want to setup automatically, run ./K2-kasten-storage.sh ; ./K3-kasten-vsphere.sh"

chmod -x ./K1-kasten.sh
