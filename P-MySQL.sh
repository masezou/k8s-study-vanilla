#!/usr/bin/env bash
# Copyright (c) 2022 masezou. All rights reserved.
#########################################################
# Force Online Install
FORCE_ONLINE=1

MYSQL_NAMESPACE=mysql
# SC = local-path / nfs-sc / vsphere-sc / longhorn
SC=vsphere-sc

SAMPLEDATA=1

#REGISTRYURL=192.168.133.2:5000

#########################################################
kubectl get ns | grep ${MYSQL_NAMESPACE}
retvalsvc=$?
if [ ${retvalsvc} -ne 0 ]; then

	# Checking Storage Class availability
	SCDEFAULT=$(kubectl get sc | grep default | cut -d " " -f1)
	kubectl get sc -n ${MYSQL_NAMESPACE} | grep ${SC}
	retvalsc=$?
	if [ ${retvalsc} -ne 0 ]; then
		echo -e "\e[31m Switching to default storage class \e[m"
		SC=${SCDEFAULT}
		echo ${SC}
	fi

	if [ -z ${REGISTRYURL} ]; then
		REGISTRYHOST=$(kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_host}')
		REIGSTRYPORT=$(kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_port}')
		REGISTRYURL=${REGISTRYHOST}:${REIGSTRYPORT}
		curl -s -X GET http://${REGISTRYURL}/v2/_catalog | grep mysql
		retvalcheck=$?
		if [ ${retvalcheck} -eq 0 ]; then
			ONLINE=0
		else
			ONLINE=1
		fi
		if [ ! -z ${FORCE_ONLINE} ]; then
			ONLINE=1
		fi
	fi

	### Install command check ####
	if type "kubectl" >/dev/null 2>&1; then
		echo "kubectl was already installed"
	else
		echo "kubectl was not found. Please install kubectl and re-run"
		exit 255
	fi

	if type "helm" >/dev/null 2>&1; then
		echo "helm was already installed"
	else
		if [ ! -f /usr/local/bin/helm ]; then
			curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /etc/apt/keyrings/helm.gpg >/dev/null
			apt install apt-transport-https --yes
			echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
			apt update
			apt -y install helm
			helm version
			helm completion bash >/etc/bash_completion.d/helm
			source /etc/bash_completion.d/helm
			helm repo add bitnami https://charts.bitnami.com/bitnami
			helm repo update
		fi
	fi

	helm repo add bitnami https://charts.bitnami.com/bitnami
	if [ ${ONLINE} -eq 0 ]; then
		MYSQLHELMVER=9.18.0
		helm fetch bitnami/mysql --version=${MYSQLHELMVER}
		MYSQLCHART=$(ls mysql-${MYSQLHELMVER}.tgz)
		helm install --create-namespace --namespace ${MYSQL_NAMESPACE} mysql-release ${MYSQLCHART} --set auth.rootPassword="Password00!" --set auth.username=admin --set auth.password="Password00!" --set primary.service.type=LoadBalancer --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRYURL}
	else
		helm install --create-namespace --namespace ${MYSQL_NAMESPACE} mysql-release bitnami/mysql --set auth.rootPassword="Password00!" --set auth.username=admin --set auth.password="Password00!" --set primary.service.type=LoadBalancer --set global.storageClass=${SC}
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
fi

EXTERNALIP=$(kubectl -n ${MYSQL_NAMESPACE} get svc mysql-release -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
echo $EXTERNALIP

apt -y install mysql-client-core-8.0

if [ ${retvalsvc} -ne 0 ]; then
	if [ ${SAMPLEDATA} -eq 1 ]; then
		echo "Import Test data (world)"
		wget https://downloads.mysql.com/docs/world-db.tar.gz
		tar xfz world-db.tar.gz
		MYSQL_ROOT_PASSWORD=$(kubectl get secret --namespace ${MYSQL_NAMESPACE} mysql-release -o jsonpath="{.data.mysql-root-password}" | base64 --decode)
		mysql -h $EXTERNALIP -uroot -p"$MYSQL_ROOT_PASSWORD" <world-db/world.sql
		rm -rf ./world-db/ ./world-db.tar.gz
	fi
fi

DNSDOMAINNAME=$(kubectl -n external-dns get deployments.apps --output="jsonpath={.items[*].spec.template.spec.containers }" | jq | grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1)
if [ ${retvalsvc} -ne 0 ]; then
	if [ ! -z ${DNSDOMAINNAME} ]; then
		kubectl -n ${MYSQL_NAMESPACE} annotate service mysql-release \
			external-dns.alpha.kubernetes.io/hostname=${MYSQL_NAMESPACE}.${DNSDOMAINNAME}
	fi
fi
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
