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

kubectl get volumesnapshotclass | grep csi-cephfsplugin-snapclass
retval3=$?
if [ ${retval3} -eq 0 ]; then
kubectl annotate volumesnapshotclass csi-cephfsplugin-snapclass \
    k10.kasten.io/is-snapshot-class=true
fi

kubectl get volumesnapshotclass | grep longhorn
retval4=$?
if [ ${retval4} -eq 0 ]; then
kubectl annotate volumesnapshotclass longhorn \
    k10.kasten.io/is-snapshot-class=true
fi

curl https://docs.kasten.io/tools/k10_primer.sh | bash
rm k10primer.yaml

# Install Kasten
kubectl create namespace kasten-io
PERSISTENTCHK=0
kubectl get sc | grep default | grep csi-hostpath-sc
retval7=$?
if [ ${retval7} -eq 0 ]; then
PERSISTENTCHK=1
fi
kubectl get sc | grep default | grep nfs-csi
retval8=$?
if [ ${retval8} -eq 0 ]; then
PERSISTENTCHK=1
fi

if [ ${PERSISTENTCHK} -eq 1 ]; then
echo "Install to volumePermissions.enabled node environment"
helm install k10 kasten/k10 --namespace=kasten-io \
--set gateway.insecureDisableSSLVerify=true \
--set global.persistence.size=40G \
--set auth.tokenAuth.enabled=true \
--set externalGateway.create=true \
--set ingress.create=true \
--set grafana.enabled=true \
--set services.securityContext.runAsUser=0 \
--set services.securityContext.fsGroup=0 \
--set prometheus.server.securityContext.runAsUser=0 \
--set prometheus.server.securityContext.runAsGroup=0 \
--set prometheus.server.securityContext.runAsNonRoot=false \
--set prometheus.server.securityContext.fsGroup=0
#--set injectKanisterSidecar.enabled=true
else
echo "Install to usual node environment"
helm install k10 kasten/k10 --namespace=kasten-io \
--set gateway.insecureDisableSSLVerify=true \
--set global.persistence.size=40G \
--set auth.tokenAuth.enabled=true \
--set externalGateway.create=true \
--set ingress.create=true \
--set grafana.enabled=true
#--set services.securityContext.runAsUser=0 \
#--set services.securityContext.fsGroup=0 \
#--set prometheus.server.securityContext.runAsUser=0 \
#--set prometheus.server.securityContext.runAsGroup=0 \
#--set prometheus.server.securityContext.runAsNonRoot=false \
#--set prometheus.server.securityContext.fsGroup=0 \
#--set injectKanisterSidecar.enabled=true
fi

# define NFS storage
kubectl get sc | grep nfs-csi
retval9=$?
if [ ${retval9} -eq 0 ]; then
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

echo "Following is login token"
sa_secret=$(kubectl get serviceaccount k10-k10 -o jsonpath="{.secrets[0].name}" --namespace kasten-io)
kubectl get secret $sa_secret --namespace kasten-io -ojsonpath="{.data.token}{'\n'}" | base64 --decode > k10-k10.token
echo "" >> k10-k10.token
cat k10-k10.token
echo
kubectl get svc gateway-ext --namespace kasten-io -o wide
kubectl -n kasten-io get ingress
kubectl get pvc -n kasten-io

helm -n kasten-io get values k10

EXTERNALIP=`kubectl -n kasten-io get ingress | awk '{print $4}' | tail -n 1`

echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "Confirm wordpress kasten is running with kubectl get pods --namespace kasten-io"
echo -e "\e[31m Open your browser http://${EXTERNALIP}/k10/ \e[m"
echo "then input login token"
echo -e "\e[31m cat k10-k10.token \e[m"
echo ""
echo "If you want to setup automatically, run ./K2-kasten-storage.sh ; ./K3-kasten-vsphere.sh"

chmod -x ./K1-kasten.sh
