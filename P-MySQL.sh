#!/usr/bin/env bash

#########################################################
# Force Online Install
#FORCE_ONLINE=1

MYSQL_NAMESPACE=mysql
# SC = csi-hostpath-sc / local-path / nfs-csi / vsphere-sc / example-vanilla-rwo-filesystem-sc / cstor-csi-disk
SC=vsphere-sc

SAMPLEDATA=0

#REGISTRYURL=192.168.133.2:5000

#########################################################
if [ -z ${REGISTRYURL} ]; then
REGISTRYHOST=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_host}'`
REIGSTRYPORT=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_port}'`
REGISTRYURL=${REGISTRYHOST}:${REIGSTRYPORT}
curl -s  -X GET http://${REGISTRYURL}/v2/_catalog |grep mysql
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
kubectl create namespace ${MYSQL_NAMESPACE}
if [ ${ONLINE} -eq 0 ]; then
helm fetch bitnami/mysql
MYSQLCHART=`ls mysql-8.9.0.tgz`
if [ ${SC} = csi-hostpath-sc ]; then
helm install --namespace ${MYSQL_NAMESPACE} mysql-release ${MYSQLCHART} --set primary.service.type=LoadBalancer --set global.storageClass=${SC} --set volumePermissions.enabled=true --set global.imageRegistry=${REGISTRYURL}
else
helm install --namespace ${MYSQL_NAMESPACE} mysql-release ${MYSQLCHART} --set primary.service.type=LoadBalancer --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRYURL}
fi
else
if [ ${SC} = csi-hostpath-sc ]; then
helm install --namespace ${MYSQL_NAMESPACE} mysql-release bitnami/mysql --set primary.service.type=LoadBalancer --set global.storageClass=${SC} --set volumePermissions.enabled=tru
else
helm install --namespace ${MYSQL_NAMESPACE} mysql-release bitnami/mysql --set primary.service.type=LoadBalancer --set global.storageClass=${SC}
fi
fi

sleep 5
kubectl -n ${MYSQL_NAMESPACE} get pod,pvc
while [ "$(kubectl -n ${MYSQL_NAMESPACE} get pod mysql-release-0 --output="jsonpath={.status.containerStatuses[*].ready}" | cut -d' ' -f2)" != "true" ]; do
        echo "Deploying MySQL, Please wait...."
    kubectl get pod,pvc -n ${MYSQL_NAMESPACE}
        sleep 30
done
    kubectl get pod,pvc -n ${MYSQL_NAMESPACE}
sleep 5


kubectl -n ${MYSQL_NAMESPACE} wait pod -l app.kubernetes\.io\/name=mysql --for condition=Ready

EXTERNALIP=`kubectl -n ${MYSQL_NAMESPACE} get svc mysql-release | awk '{print $4}' | tail -n 1`
echo $EXTERNALIP
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
kubectl -n ${MYSQL_NAMESPACE} annotate service  mysql-release  \
    external-dns.alpha.kubernetes.io/hostname=${MYSQL_NAMESPACE}.${DNSDOMAINNAME}
kubectl images -n ${MYSQL_NAMESPACE}
echo ""
echo "*************************************************************************************"
MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace ${MYSQL_NAMESPACE} mysql-release -o jsonpath="{.data.mysql-root-password}" | base64 --decode)
echo ""
echo "MySQL Host: ${MYSQL_NAMESPACE}.${DNSDOMAINNAME} / ${EXTERNALIP}"
echo "Credential: root / ${MYSQL_ROOT_PASSWORD}"
echo ""
echo "How to connect"
echo -n 'MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace'
echo -n " ${MYSQL_NAMESPACE} "
echo -n 'mysql-release -o jsonpath="{.data.mysql-root-password}" | base64 --decode)'
echo ""
echo -n "mysql -h $EXTERNALIP -uroot -p"
echo -n '"$MYSQL_ROOT_PASSWORD"'
echo ""

