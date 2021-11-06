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

PGNAMESPACE=postgresql-app
SC=vsphere-sc

helm repo add bitnami https://charts.bitnami.com/bitnami
kubectl create namespace ${PGNAMESPACE}
if [ ${SC} = csi-hostpath-sc ]; then
helm install --namespace ${PGNAMESPACE} postgres bitnami/postgresql --set volumePermissions.enabled=true --set global.storageClass=${SC}
else
helm install --namespace ${PGNAMESPACE} postgres bitnami/postgresql --set global.storageClass=${SC}
fi
kubectl annotate statefulset postgres-postgresql kanister.kasten.io/blueprint='postgresql-hooks' \
     --namespace=${PGNAMESPACE}
