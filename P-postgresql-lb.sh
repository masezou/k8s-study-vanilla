#!/usr/bin/env bash

#########################################################

PGNAMESPACE=postgresql-lb
# SC = csi-hostpath-sc / local-path / nfs-csi / vsphere-sc / cstor-csi-disk
SC=vsphere-sc

SAMPLEDATA=0

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

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
kubectl create namespace ${PGNAMESPACE}
if [ ${SC} = csi-hostpath-sc ]; then
helm install --namespace ${PGNAMESPACE} postgres bitnami/postgresql --version 9.1.1 --set volumePermissions.enabled=true --set global.storageClass=${SC}
else
helm install --namespace ${PGNAMESPACE} postgres bitnami/postgresql --version 9.1.1 --set global.storageClass=${SC}
fi

sleep 5
kubectl -n ${PGNAMESPACE} get pod,pvc
while [ "$(kubectl -n ${PGNAMESPACE} get pod postgres-postgresql-0 --output="jsonpath={.status.containerStatuses[*].ready}" | cut -d' ' -f2)" != "true" ]; do
        echo "Deploying PostgreSQL, Please wait...."
    kubectl get pod,pvc -n ${PGNAMESPACE}
        sleep 30
done
    kubectl get pod,pvc -n ${PGNAMESPACE}
sleep 5


if [ ${SAMPLEDATA} -eq 1 ]; then
export POSTGRES_PASSWORD=$(kubectl get secret --namespace ${PGNAMESPACE} postgres-postgresql -o jsonpath="{.data.postgresql-password}" | base64 --decode)
kubectl port-forward --namespace  ${PGNAMESPACE} svc/postgres-postgresql 5432:5432 &
PGPASSWORD="$POSTGRES_PASSWORD" createdb --host 127.0.0.1 -U postgres pgbenchdb
PGPASSWORD="$POSTGRES_PASSWORD" pgbench --host 127.0.0.1 -U postgres  -i pgbenchdb
PGPASSWORD="$POSTGRES_PASSWORD" pgbench --host 127.0.0.1 -U postgres  -c 10 -t 1000  pgbenchdb
fi

kubectl --namespace ${PGNAMESPACE} annotate statefulset/postgres-postgresql \
    kanister.kasten.io/blueprint=postgres-bp
