#!/usr/bin/env bash
# Copyright (c) 2022 masezou. All rights reserved.
#########################################################
# Force Online Install
FORCE_ONLINE=1

# namespace. namespace will be used with hostname
WPNAMESPACE=blog1

# SC =  local-path / nfs-sc / vsphere-sc / longhorn
SC=vsphere-sc

#REGISTRY=192.168.133.2:5000

#########################################################
kubectl get ns | grep ${WPNAMESPACE}
retvalsvc=$?
if [ ${retvalsvc} -ne 0 ]; then

	# Checking Storage Class availability
	SCDEFAULT=$(kubectl get sc | grep default | cut -d " " -f1)
	kubectl get sc -n ${WPNAMESPACE} | grep ${SC}
	retvalsc=$?
	if [ ${retvalsc} -ne 0 ]; then
		echo -e "\e[31m Switching to default storage class \e[m"
		SC=${SCDEFAULT}
		echo ${SC}
	fi

	#K3S registry setting
	if [ -f /etc/rancher/k3s/registries.yaml ]; then
		REGISTRY=$(grep http /etc/rancher/k3s/registries.yaml | cut -d "/" -f 3 | cut -d "\"" -f 1)
		REGISTRYURL=http://${REGISTRY}
	fi

	if [ -z ${REGISTRY} ]; then
		#REGISTRYHOST=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_host}'`
		#REGISTRYPORT=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_port}'`
		REGISTRYHOST=$(ls --ignore docker.io /etc/containerd/certs.d/ | cut -d ":" -f1)
		REGISTRYPORT=$(ls --ignore docker.io /etc/containerd/certs.d/ | cut -d ":" -f2)
		REGISTRY=${REGISTRYHOST}:${REGISTRYPORT}
		curl -s -X GET http://${REGISTRY}/v2/_catalog | grep wordpress
		retvalcheck=$?
		if [ ${retvalcheck} -eq 0 ]; then
			ONLINE=0
		else
			ONLINE=1
		fi
		if [ ! -z ${FORCE_ONLINE} ]; then
			ONLINE=1
		fi
	else
		ONLINE=0
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

	DNSDOMAINNAME=$(kubectl -n external-dns get deployments.apps --output="jsonpath={.items[*].spec.template.spec.containers }" | jq | grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1)
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm repo update

	cat <<EOF >values.yaml
wordpressExtraConfigContent: |
  @ini_set( 'upload_max_size' , '1024M' );
  @ini_set( 'post_max_size', '1024M');
  @ini_set( 'memory_limit', '1024M' );
  @ini_set( 'max_execution_time', '0' );
  @ini_set( 'max_input_time', '0' );
  define( 'WP_AUTO_UPDATE_CORE', true );
extraEnvVars:
  - name: PHP_POST_MAX_SIZE
    value: 1024M
  - name: PHP_UPLOAD_MAX_FILESIZE
    value: 1024M
EOF

	if [ ${ONLINE} -eq 0 ]; then
		# helm search repo bitnami/wordpress  --version=14.0.9
		WPHELMVER=19.2.3
		helm fetch bitnami/wordpress --version=${WPHELMVER}
		WPCHART=$(ls wordpress-${WPHELMVER}.tgz)
		helm install wp-release ${WPCHART} --create-namespace --namespace ${WPNAMESPACE} --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRY} --set wordpressUsername=bloguser --set wordpressPassword="Password00!" --set wordpressEmail=bloguser@${DNSDOMAINNAME} --set wordpressFirstName=John --set wordpressLastName=Doe --set wordpressBlogName=${WPNAMESPACE} --set mariadb.auth.rootPassword="Password00!" --set mariadb.auth.username=admin --set mariadb.auth.password="Password00!" -f values.yaml
	else
		helm install wp-release bitnami/wordpress --create-namespace --namespace ${WPNAMESPACE} --set global.storageClass=${SC} --set wordpressUsername=bloguser --set wordpressPassword="Password00!" --set wordpressEmail=bloguser@${DNSDOMAINNAME} --set wordpressFirstName=John --set wordpressLastName=Doe --set wordpressBlogName=${WPNAMESPACE} --set mariadb.auth.rootPassword="Password00!" --set mariadb.auth.username=admin --set mariadb.auth.password="Password00!" -f values.yaml
	fi
	mv values.yaml values-wp.yaml
	sleep 5
	kubectl get pod,pvc -n ${WPNAMESPACE}
	echo "Initial sleep 30s"
	sleep 30
	kubectl -n ${WPNAMESPACE} get pod,pvc
	while [ "$(kubectl get pod -n ${WPNAMESPACE} wp-release-mariadb-0 --output="jsonpath={.status.containerStatuses[*].ready}" | cut -d' ' -f2)" != "true" ]; do
		echo "Deploying Stateful mariadb, Please wait...."
		kubectl get pod,pvc -n ${WPNAMESPACE}
		sleep 30
	done
	kubectl get pod,pvc -n ${WPNAMESPACE}
	kubectl get pvc,pv -n ${WPNAMESPACE}
	cd ..
fi
EXTERNALIP=$(kubectl -n ${WPNAMESPACE} get service wp-release-wordpress -o jsonpath="{.status.loadBalancer.ingress[*].ip}")

WPHOST=${WPNAMESPACE}
if [ ${retvalsvc} -ne 0 ]; then
	if [ ! -z ${DNSDOMAINNAME} ]; then
		kubectl -n ${WPNAMESPACE} annotate service wp-release-wordpress \
			external-dns.alpha.kubernetes.io/hostname=${WPHOST}.${DNSDOMAINNAME}
	fi
	#kubectl -n ${WPNAMESPACE} wait pod -l app=wordpress --for condition=Ready --timeout 180s
fi
apt -y install mysql-client-core-8.0 lynx
sleep 30
kubectl images -n ${WPNAMESPACE}
kubectl -n ${WPNAMESPACE} get pod,pvc,svc
echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "Confirm wordpress pod and mysql pod are running with kubectl get pod -A"
echo "Open http://${EXTERNALIP}/wp-admin/"
if [ ! -z ${DNSDOMAINNAME} ]; then
	echo "or"
	echo "Open http://${WPHOST}.${DNSDOMAINNAME}/wp-admin/"
fi
echo ""
echo "Credential:"
echo "Username:"
echo "user"
echo "Password:"
echo $(kubectl get secret --namespace ${WPNAMESPACE} wp-release-wordpress -o jsonpath="{.data.wordpress-password}" | base64 --decode)
echo ""
echo ""
echo ""
