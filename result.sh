#!/usr/bin/env bash
# Copyright (c) 2022 masezou. All rights reserved.

if [ ! -f ~/.kube/config ]; then
	echo "There is no kubeconfig. exit ..."
	exit 0
fi

LOCALIPADDR=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
DNSDOMAINNAME=$(kubectl -n external-dns get deployments.apps --output="jsonpath={.items[*].spec.template.spec.containers }" | jq | grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1)
DNSHOSTIP=$(kubectl -n external-dns get deployments.apps --output="jsonpath={.items[*].spec.template.spec.containers }" | jq | grep rfc2136-host | cut -d "=" -f 2 | cut -d "\"" -f 1)
DASHBOARD_EXTERNALIP=$(kubectl -n kubernetes-dashboard get service dashboard-service-lb -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
DASHBOARD_FQDN=$(kubectl -n kubernetes-dashboard get svc dashboard-service-lb --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4)
#REGISTRYHOST=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_host}'`
#K3S registry setting
if [ -f /etc/rancher/k3s/registries.yaml ]; then
	REGISTRY=$(grep http /etc/rancher/k3s/registries.yaml | cut -d "/" -f 3 | cut -d "\"" -f 1)
	REGISTRYURL=http://${REGISTRY}
fi
if [ -z ${REGISTRY} ]; then
	REGISTRYHOST=$(ls --ignore docker.io /etc/containerd/certs.d/ | cut -d ":" -f1)
	#REGISTRYPORT=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_port}'`
	REGISTRYPORT=$(ls --ignore docker.io /etc/containerd/certs.d/ | cut -d ":" -f2)
	REGISTRY=${REGISTRYHOST}:${REGISTRYPORT}
	REGISTRYURL=${REGISTRYHOST}:${REGISTRYPORT}
fi
#REGISTRY_EXTERNALIP=`kubectl -n registry get service pregistry-frontend-clusterip -o jsonpath="{.status.loadBalancer.ingress[*].ip}"`
REGISTRY_FQDN=$(kubectl -n registry get svc pregistry-frontend-clusterip --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4)
#REGISTRY_FQDN=registryfe.${DNSDOMAINNAME}
KEYCLOAK_EXTERNALIP=`kubectl -n keycloak get service keycloak -o jsonpath="{.status.loadBalancer.ingress[*].ip}"`
KEYCLOAK_FQDN=$(kubectl -n keycloak get svc keycloak --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4)
#KEYCLOAK_FQDN=keycloak.${DNSDOMAINNAME}
LONGHORN_EXTERNALIP=$(kubectl -n longhorn-system get svc longhorn-frontend -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
LONGHORN_FQDN=$(kubectl -n longhorn-system get svc longhorn-frontend --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4)
PROMETHEUS_IP=$(kubectl -n monitoring get service prometheus-kube-prometheus-prometheus -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
PROMETHEUS_FQDN=$(kubectl -n monitoring get service prometheus-kube-prometheus-prometheus --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4)
KUBEMETRICS_IP=$(kubectl -n monitoring get service prometheus-kube-state-metrics -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
KUBEMETRICS_FQDN=$(kubectl -n monitoring get service prometheus-kube-state-metrics --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4)
GRAFANA_IP=$(kubectl -n monitoring get service prometheus-grafana -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
GRAFANA_FQDN=$(kubectl -n monitoring get service prometheus-grafana --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4)

echo "*************************************************************************************"
echo "Here is cluster context."
echo -e "\e[1mkubectl config get-contexts \e[m"
kubectl config get-contexts
echo ""
echo "vSphere CSI Driver info"
kubectl get sc | grep vsphere
retvspheredriver=$?
if [ ${retvspheredriver} -eq 0 ]; then
	kubectl -n vmware-system-csi describe pod $(kubectl -n vmware-system-csi get pod -l app=vsphere-csi-controller -o custom-columns=:metadata.name) | grep driver | grep Image | grep -v ID
fi
echo ""
echo -e "\e[1mmetallb loadbalancer IP address range \e[m"
kubectl -n metallb-system get configmaps config -o jsonpath='{.data.config}'
echo ""
echo ""
echo -e "\e[1mDNS Server \e[m"
echo -n "DNS Domain Name is "
echo -e "\e[32m${DNSDOMAINNAME} \e[m"
echo -n "DNS DNS IP address is "
echo -e "\e[32m${DNSHOSTIP} \e[m"
echo ""
MCLOGINUSER=miniologinuser
MCLOGINPASSWORD=miniologinuser
MINIO_ENDPOINT=https://${LOCALIPADDR}
MINIO_ENDPOINTFQDN=https://minio.${DNSDOMAINNAME}
echo -e "\e[32m Minio API endpoint is ${MINIO_ENDPOINT}:9000 \e[m"
echo "or"
echo -e "\e[32m Minio API endpoint is ${MINIO_ENDPOINTFQDN}:9000 \e[m"
echo -e "\e[32m Access Key: ${MCLOGINUSER} \e[m"
echo -e "\e[32m Secret Key: ${MCLOGINPASSWORD} \e[m"
echo ""
echo -e "\e[32m Minio console is ${MINIO_ENDPOINT}:9001 \e[m"
echo "or"
echo -e "\e[32m Minio console is ${MINIO_ENDPOINTFQDN}:9001 \e[m"
echo -e "\e[32m username: ${MCLOGINUSER} \e[m"
echo -e "\e[32m password: ${MCLOGINPASSWORD} \e[m"
echo ""
if [ ! -z ${DASHBOARD_EXTERNALIP} ]; then
	kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}" >dashboard.token
	echo "" >>dashboard.token
	echo -e "\e[1mKubernetes dashboard \e[m"
	echo -e "\e[32m https://${DASHBOARD_EXTERNALIP}/#/login  \e[m"
	echo "or"
	echo -e "\e[32m https://${DASHBOARD_FQDN}/#/login \e[m"
	echo ""
	echo -e "\e[32m login token is cat ./dashboard.token  \e[m"
	cat ./dashboard.token
	echo ""
fi
echo ""
if [ ! -z ${REGISTRYURL} ]; then
	echo -e "\e[1mRegistry \e[m"
	echo -e "\e[1mRegistry URL \e[m"
	echo -e "\e[32m ${REGISTRYURL}  \e[m"
	if [ -f /usr/bin/docker ]; then
		echo "docker check"
		grep ${REGISTRYURL} /etc/docker/daemon.json
		retvaldaemon=$?
		if [ ${retvaldaemon} -eq 0 ]; then
			echo -e "\e[32m docker was configured. \e[m"
		else
			echo -e "\e[31m docker was not configured. \e[m"
			echo -e "\e[31m You need to set registry setting in docker. \e[m"
		fi
	fi

	if [ -f /etc/rancher/k3s/registries.yaml ]; then
		echo "k3s check"
		grep ${REGISTRY} /etc/rancher/k3s/registries.yaml
		retvalk3schk=$?
		if [ ${retvalk3schk} -eq 0 ]; then
			echo -e "\e[32m containerd was configured. \e[m"
		else
			echo -e "\e[31m contained was not configured. \e[m"
			echo -e "\e[31m You need to set registry setting in /etc/rancher/k3s/registries.yaml . \e[m"
		fi
	fi

	if [ -d /etc/containerd/certs.d/ ]; then
		echo "Containerd check"
		ls -1 /etc/containerd/certs.d/ | grep -v docker.io | grep ${REGISTRYURL}
		retvalcontainerd=$?
		if [ ${retvalcontainerd} -eq 0 ]; then
			echo -e "\e[32m containerd was configured. \e[m"
		else
			echo -e "\e[31m contained was not configured. \e[m"
			echo -e "\e[31m You need to set registry setting in containerd. \e[m"
		fi
	fi
fi

echo ""
if [ ! -z ${REGISTRY_EXTERNALIP} ]; then
	echo -e "\e[1mRegistry frontend UI \e[m"
	echo -e "\e[32m http://${REGISTRY_EXTERNALIP}  \e[m"
	echo "or"
	echo -e "\e[32m http://${REGISTRY_FQDN} \e[m"
	echo ""
fi
if [ ! -z ${KEYCLOAK_FQDN} ]; then
	echo -e "\e[1mKeycloak  \e[m"
	echo -e "\e[32m http://${KEYCLOAK_FQDN}:8080 \e[m"
	echo "or"
	echo -e "\e[32m http://${KEYCLOAK_EXTERNALIP}:8080  \e[m"
	echo ""
	echo -n " login credential is "
	echo -e "\e[32m admin/admin  \e[m"
	echo ""
fi
if [ ! -z ${LONGHORN_EXTERNALIP} ]; then
	echo -e "\e[1mLonghorn dashboard \e[m"
	echo -e "\e[32m http://${LONGHORN_EXTERNALIP}/  \e[m"
#	echo "or"
#	echo -e "\e[32m http://${LONGHORN_FQDN}/ \e[m"
	echo ""
fi

if [ ! -z ${PROMETHEUS_IP} ]; then
	echo -e "\e[1mPrometheus dashboard \e[m"
	echo -e "\e[32m http://${PROMETHEUS_IP}:9090 \e[m"
	echo "or"
	echo -e "\e[32m http://${PROMETHEUS_FQDN}:9090 \e[m"
	echo ""
fi

if [ ! -z ${KUBEMETRICS_IP} ]; then
	echo -e "\e[1mKubemetrics dashboard \e[m"
	echo -e "\e[32m http://${KUBEMETRICS_IP}:8080 \e[m"
	echo "or"
	echo -e "\e[32m http://${KUBEMETRICS_FQDN}:8080 \e[m"
	echo ""
fi

if [ ! -z ${GRAFANA_IP} ]; then
	echo -e "\e[1mGrafana dashboard \e[m"
	echo -e "\e[32m http://${GRAFANA_IP} \e[m"
	echo "or"
	echo -e "\e[32m http://${GRAFANA_FQDN} \e[m"
	echo ""
	echo -e "\e[32m login credential is cat ./grafana_credential  \e[m"
	GRAFANA_LOGIN=$(
		kubectl get secret -n monitoring prometheus-grafana -o yaml | grep admin-user | cut -d ":" -f 2 | tr -d " " | base64 --decode
		echo
	)
	GRAFANA_PASS=$(
		kubectl get secret -n monitoring prometheus-grafana -o yaml | grep admin-password | cut -d ":" -f 2 | tr -d " " | base64 --decode
		echo
	)
	echo $GRAFANA_LOGIN >./grafana_credential
	echo $GRAFANA_PASS >>./grafana_credential
	cat ./grafana_credential
	echo ""
fi
echo ""
kubectl get ns kasten-io >/dev/null 2>&1
HAS_KASTEN=$?
if [ ${HAS_KASTEN} -eq 0 ]; then
	KASTENEXTERNALIP=$(kubectl -n kasten-io get svc gateway-ext -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
	KASTENFQDNURL=$(kubectl -n kasten-io get svc gateway-ext --output="jsonpath={.metadata.annotations}" | jq | grep external-dns | cut -d "\"" -f 4)
	KASTENINGRESSIP=$(kubectl get ingress -n kasten-io --output="jsonpath={.items[*].status.loadBalancer.ingress[*].ip}")
	K10INGRESHOST=$(kubectl -n kasten-io get ingress k10-ingress --output="jsonpath={.spec.rules[*].host }")
	K10INGRESPATH=$(kubectl -n kasten-io get ingress k10-ingress --output="jsonpath={.spec.rules[*].http.paths[*].path }")
	K10INGRESURL="${K10INGRESHOST}${K10INGRESPATH}"
    desired_token_secret_name=k10-k10-token
    kubectl get secret ${desired_token_secret_name} --namespace kasten-io -ojsonpath="{.data.token}" | base64 --decode ; echo > k10-k10.token
	sa_secret=$(kubectl get serviceaccount backupadmin -o jsonpath="{.secrets[0].name}")
	kubectl get secret $sa_secret -ojsonpath="{.data.token}{'\n'}" | base64 --decode >backupadmin.token
	echo "" >>backupadmin.token
	sa_secret=$(kubectl get serviceaccount backupbasic -o jsonpath="{.secrets[0].name}")
	kubectl get secret $sa_secret -ojsonpath="{.data.token}{'\n'}" | base64 --decode >backupbasic.token
	echo "" >>backupbasic.token
	sa_secret=$(kubectl get serviceaccount backupview -o jsonpath="{.secrets[0].name}")
	kubectl get secret $sa_secret -ojsonpath="{.data.token}{'\n'}" | base64 --decode >backupview.token
	echo "" >>backupview.token
	sa_secret=$(kubectl get serviceaccount nsadmin -o jsonpath="{.secrets[0].name}")
	kubectl get secret $sa_secret -ojsonpath="{.data.token}{'\n'}" | base64 --decode >nsadmin.token
	echo "" >>nsadmin.token
	sa_secret=$(kubectl get serviceaccount backup-mc-admin -o jsonpath="{.secrets[0].name}")
	kubectl get secret $sa_secret -ojsonpath="{.data.token}{'\n'}" | base64 --decode >backup-mc-admin.token
	echo "" >>backup-mc-admin.token
	sa_secret=$(kubectl get serviceaccount backup-mc-user -o jsonpath="{.secrets[0].name}")
	kubectl get secret $sa_secret -ojsonpath="{.data.token}{'\n'}" | base64 --decode >backup-mc-user.token
	echo "" >>backup-mc-user.token
	echo -e "\e[1mKasten Dashboard \e[m"
	echo -e "\e[32m Open your browser \e[m"
	echo -e "\e[32m  http://${KASTENFQDNURL}/k10/ \e[m"
	echo -e "\e[32m  http://${KASTENEXTERNALIP}/k10/ \e[m"
	echo -e "\e[32m  http://${K10INGRESURL} \e[m"
	echo -e "\e[32m  https://${K10INGRESURL} \e[m"
	echo "then input login token"
	echo -e "\e[32m cat ./k10-k10.token \e[m"
	cat ./k10-k10.token
fi
echo ""
echo -e "\e[1mKubeconfig \e[m"
echo -e "\e[32m ~/.kube/config \e[m"
echo " You can access Kubernetes from your desktop!"
