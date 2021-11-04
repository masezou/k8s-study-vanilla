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

PGNAMESPACE=postgresql-lb
SC=csi-hostpath-sc

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
kubectl create namespace ${PGNAMESPACE}
helm install --namespace ${PGNAMESPACE} postgres bitnami/postgresql --version 9.1.1 --set global.storageClass=${SC}
kubectl --namespace ${PGNAMESPACE} annotate statefulset/postgres-postgresql \
    kanister.kasten.io/blueprint=postgres-bp
