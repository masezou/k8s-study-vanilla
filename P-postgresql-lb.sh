#!/usr/bin/env bash

PGNAMESPACE=postgresql-lb
# SC = csi-hostpath-sc / local-path / nfs-csi / vsphere-sc / cstor-csi-disk
SC=vsphere-sc

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

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
kubectl create namespace ${PGNAMESPACE}
if [ ${SC} = csi-hostpath-sc ]; then
helm install --namespace ${PGNAMESPACE} postgres bitnami/postgresql --version 9.1.1 --set volumePermissions.enabled=true --set global.storageClass=${SC}
else
helm install --namespace ${PGNAMESPACE} postgres bitnami/postgresql --version 9.1.1 --set global.storageClass=${SC}
fi
kubectl --namespace ${PGNAMESPACE} annotate statefulset/postgres-postgresql \
    kanister.kasten.io/blueprint=postgres-bp
