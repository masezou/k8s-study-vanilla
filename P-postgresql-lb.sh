#!/usr/bin/env bash

#########################################################
# Force Online Install
#FORCE_ONLINE=1

PGNAMESPACE=postgresql-lb
# SC = csi-hostpath-sc / local-path / nfs-csi / vsphere-sc / example-vanilla-rwo-filesystem-sc / cstor-csi-disk
SC=vsphere-sc

SAMPLEDATA=0

#REGISTRYURL=192.168.133.2:5000

#########################################################
if [ -z ${REGISTRYURL} ]; then
REGISTRYHOST=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_host}'`
REIGSTRYPORT=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_port}'`
REGISTRYURL=${REGISTRYHOST}:${REIGSTRYPORT}
curl -s  -X GET http://${REGISTRYURL}/v2/_catalog |grep postgresql
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
# https://artifacthub.io/packages/helm/bitnami/postgresql
helm repo update
kubectl create namespace ${PGNAMESPACE}
if [ ${ONLINE} -eq 0 ]; then
helm fetch bitnami/postgresql --version=9.1.1
PGSQLCHART=`ls postgresql-9.1.1.tgz`
if [ ${SC} = csi-hostpath-sc ]; then
helm install --namespace ${PGNAMESPACE} postgres ${PGSQLCHART} --set service.type=LoadBalancer --set volumePermissions.enabled=true --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRYURL}
else
helm install --namespace ${PGNAMESPACE} postgres ${PGSQLCHART} --set service.type=LoadBalancer --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRYURL}
fi
else
if [ ${SC} = csi-hostpath-sc ]; then
helm install --namespace ${PGNAMESPACE} postgres bitnami/postgresql --version 9.1.1 --set service.type=LoadBalancer --set volumePermissions.enabled=true --set global.storageClass=${SC}
else
helm install --namespace ${PGNAMESPACE} postgres bitnami/postgresql --version 9.1.1 --set service.type=LoadBalancer --set global.storageClass=${SC}
fi
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

EXTERNALIP=`kubectl -n ${PGNAMESPACE} get svc postgres-postgresql | awk '{print $4}' | tail -n 1`
echo $EXTERNALIP
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
kubectl -n ${PGNAMESPACE} annotate service postgres-postgresql \
    external-dns.alpha.kubernetes.io/hostname=${PGNAMESPACE}.${DNSDOMAINNAME}


if [ ${SAMPLEDATA} -eq 1 ]; then
export POSTGRES_PASSWORD=$(kubectl get secret --namespace ${PGNAMESPACE} postgres-postgresql -o jsonpath="{.data.postgresql-password}" | base64 --decode)
kubectl port-forward --namespace  ${PGNAMESPACE} svc/postgres-postgresql 5432:5432 &
PGPASSWORD="$POSTGRES_PASSWORD" createdb --host 127.0.0.1 -U postgres pgbenchdb
PGPASSWORD="$POSTGRES_PASSWORD" pgbench --host 127.0.0.1 -U postgres  -i pgbenchdb
PGPASSWORD="$POSTGRES_PASSWORD" pgbench --host 127.0.0.1 -U postgres  -c 10 -t 1000  pgbenchdb
fi

if [ ${ONLINE} -eq 0 ]; then
kubectl images -n ${PGNAMESPACE}
fi

echo ""
echo "*************************************************************************************"
export POSTGRES_PASSWORD=$(kubectl get secret --namespace ${PGNAMESPACE} postgres-postgresql -o jsonpath="{.data.postgresql-password}" | base64 --decode)
echo ""
echo "Postgresql Host: ${PGNAMESPACE}.${DNSDOMAINNAME} / ${EXTERNALIP}"
echo "Credential: postgres / ${POSTGRES_PASSWORD}"
echo ""
echo "How to connect"
echo -n 'export POSTGRES_PASSWORD=$(kubectl get secret --namespace '
echo -n "${PGNAMESPACE} "
echo -n 'postgres-postgresql -o jsonpath="{.data.postgresql-password}" | base64 --decode)'
echo ""
echo -n 'PGPASSWORD=${POSTGRES_PASSWORD} '
echo "psql --host ${EXTERNALIP} -U postgres -d postgres -p 5432"
echo ""
