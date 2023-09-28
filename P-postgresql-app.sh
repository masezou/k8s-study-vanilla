#!/usr/bin/env bash
# Copyright (c) 2022 masezou. All rights reserved.
#########################################################
# Force Online Install
FORCE_ONLINE=1

PGNAMESPACE=postgresql-app
# SC = local-path / nfs-sc / vsphere-sc / longhorn
SC=vsphere-sc

ENABLEWAL=1
SAMPLEDATA=1

#REGISTRYURL=192.168.133.2:5000

#########################################################
kubectl get ns | grep ${PGNAMESPACE}
retvalsvc=$?
if [ ${retvalsvc} -ne 0 ]; then

	# Checking Storage Class availability
	SCDEFAULT=$(kubectl get sc | grep default | cut -d " " -f1)
	kubectl get sc -n ${PGNAMESPACE} | grep ${SC}
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
		curl -s -X GET http://${REGISTRYURL}/v2/_catalog | grep postgresql
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

	if [ ${ENABLEWAL} -eq 1 ]; then
		# Create configmap
		cat <<EOF >values.yaml
primary:
  extendedConfiguration: |-
    archive_mode = on
    archive_command = 'envdir /bitnami/postgresql/data/env wal-e wal-push %p'
    archive_timeout = 60
    wal_level = archive
EOF
		WALOP="-f values.yaml"
	else
		WALOP=""
	fi
	helm repo add bitnami https://charts.bitnami.com/bitnami
	# https://artifacthub.io/packages/helm/bitnami/postgresql
	if [ ${ONLINE} -eq 0 ]; then
		POSGRESSHELMVER=12.10.10
		helm fetch bitnami/postgresql --version=${POSGRESSHELMVER}
		PGSQLCHART=$(ls postgresql-${POSGRESSHELMVER}.tgz)
		helm install --create-namespace --namespace ${PGNAMESPACE} postgres-postgresql ${PGSQLCHART} --set global.postgresql.auth.postgresPassword="Password00!" --set global.postgresql.auth.username=admin --set global.postgresql.auth.password="Password00!" --set primary.service.type=LoadBalancer --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRYURL} ${WALOP}
	else
		helm install --create-namespace --namespace ${PGNAMESPACE} postgres bitnami/postgresql --set global.postgresql.auth.postgresPassword="Password00!" --set global.postgresql.auth.username=admin --set global.postgresql.auth.password="Password00!" --set primary.service.type=LoadBalancer --set global.storageClass=${SC} ${WALOP}
	fi
	mv values.yaml values-postgresql.yaml
	sleep 5
	kubectl -n ${PGNAMESPACE} get pod,pvc
	while [ "$(kubectl -n ${PGNAMESPACE} get pod postgres-postgresql-0 --output="jsonpath={.status.containerStatuses[*].ready}" | cut -d' ' -f2)" != "true" ]; do
		echo "Deploying PostgreSQL, Please wait...."
		kubectl get pod,pvc -n ${PGNAMESPACE}
		sleep 30
	done
	kubectl get pod,pvc -n ${PGNAMESPACE}
	sleep 5

fi
EXTERNALIP=$(kubectl -n ${PGNAMESPACE} get svc postgres-postgresql -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
echo $EXTERNALIP
DNSDOMAINNAME=$(kubectl -n external-dns get deployments.apps --output="jsonpath={.items[*].spec.template.spec.containers }" | jq | grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1)
if [ ${retvalsvc} -ne 0 ]; then
	if [ ! -z ${DNSDOMAINNAME} ]; then
		kubectl -n ${PGNAMESPACE} annotate service postgres-postgresql \
			external-dns.alpha.kubernetes.io/hostname=${PGNAMESPACE}.${DNSDOMAINNAME}
	fi
fi
if [ ${retvalsvc} -ne 0 ]; then
	if [ ${SAMPLEDATA} -eq 1 ]; then
		echo "Import Test data (dvdrental)"
		#export POSTGRES_PASSWORD=$(kubectl get secret --namespace ${PGNAMESPACE} postgres-postgresql -o jsonpath="{.data.postgresql-password}" | base64 --decode)
		#kubectl port-forward --namespace  ${PGNAMESPACE} svc/postgres-postgresql 5432:5432 &
		#PGPASSWORD="$POSTGRES_PASSWORD" createdb --host 127.0.0.1 -U postgres pgbenchdb
		#PGPASSWORD="$POSTGRES_PASSWORD" pgbench --host 127.0.0.1 -U postgres  -i pgbenchdb
		#PGPASSWORD="$POSTGRES_PASSWORD" pgbench --host 127.0.0.1 -U postgres  -c 10 -t 1000  pgbenchdb

		apt -y install unzip postgresql-client-common postgresql-client
		export POSTGRES_PASSWORD=$(kubectl get secret --namespace ${PGNAMESPACE} postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)
		PGPASSWORD=${POSTGRES_PASSWORD} psql --host $EXTERNALIP -U postgres -d postgres -p 5432 -c "create database dvdrental"
		wget https://www.postgresqltutorial.com/wp-content/uploads/2019/05/dvdrental.zip
		unzip dvdrental.zip
		PGPASSWORD=${POSTGRES_PASSWORD} pg_restore --host $EXTERNALIP -U postgres -d dvdrental ./dvdrental.tar
		rm -rf ./dvdrental.zip ./dvdrental.tar
	fi
fi

kubectl images -n ${PGNAMESPACE}

echo ""
echo "*************************************************************************************"
export POSTGRES_PASSWORD=$(kubectl get secret --namespace ${PGNAMESPACE} postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)
echo ""
echo "Postgresql Host: ${PGNAMESPACE}.${DNSDOMAINNAME} / ${EXTERNALIP}"
echo "Credential: postgres / ${POSTGRES_PASSWORD}"
echo ""
echo "How to connect"
echo -n 'export POSTGRES_PASSWORD=$(kubectl get secret --namespace '
echo -n "${PGNAMESPACE} "
echo -n 'postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)'
echo ""
echo -n 'PGPASSWORD=${POSTGRES_PASSWORD} '
echo "psql --host ${EXTERNALIP} -U postgres -d postgres -p 5432"
echo ""
echo ""
echo ""
