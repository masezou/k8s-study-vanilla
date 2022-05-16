#!/usr/bin/env bash
#########################################################
# Force Online Install
#FORCE_ONLINE=1

NAMESPACE=pacman

# SC = csi-hostpath-sc / local-hostpath / local-path / nfs-sc / nfs-csi / vsphere-sc / example-vanilla-rwo-filesystem-sc / cstor-csi-disk / synology-iscsi-storage / synostorage-smb
SC=vsphere-sc

#REGISTRYURL=192.168.133.2:5000

#########################################################
kubectl get ns | grep ${NAMESPACE}
retvalsvc=$?
if [ ${retvalsvc} -ne 0 ]; then

	# Checking Storage Class availability
	SCDEFAULT=$(kubectl get sc | grep default | cut -d " " -f1)
	kubectl get sc | grep ${SC}
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
		curl -s -X GET http://${REGISTRYURL}/v2/_catalog | grep mongodb
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

	git clone https://github.com/saintdle/pacman-tanzu --depth 1
	cd pacman-tanzu/
	if [ ${ONLINE} -eq 0 ]; then
		sed -i -e "s/quay.io/${REGISTRYURL}/g" deployments/pacman-deployment.yaml
		sed -i -e "s/docker.io/${REGISTRYURL}/g" deployments/mongo-deployment.yaml
		sed -i -e "s@bitnami/mongodb@${REGISTRYURL}/bitnami/mongodb@g" deployments/mongo-deployment.yaml
	fi
	bash ./pacman-install.sh
	kubectl get pvc -n ${NAMESPACE}
	kubectl get svc -n ${NAMESPACE}
	kubectl -n pacman wait pod -l name=${NAMESPACE} --for condition=Ready

	DNSDOMAINNAME=$(kubectl -n external-dns get deployments.apps --output="jsonpath={.items[*].spec.template.spec.containers }" | jq | grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1)
	if [ ${retvalsvc} -ne 0 ]; then
		if [ ! -z ${DNSDOMAINNAME} ]; then
			kubectl -n pacman annotate service pacman external-dns.alpha.kubernetes.io/hostname=pacman.${DNSDOMAINNAME}
		fi
	fi

	sleep 30
	cd ..
fi

kubectl images -n ${NAMESPACE}
echo ""
echo "*************************************************************************************"
echo "Next Step"
PACMAN_EXTERNALIP=$(kubectl -n ${NAMESPACE} get svc pacman | awk '{print $4}' | tail -n 1)
echo "http://${PACMAN_EXTERNALIP}/"
if [ ! -z ${DNSDOMAINNAME} ]; then
	echo "or"
	echo "http://pacman.${DNSDOMAINNAME}/"
fi
echo ""
echo ""

chmod -x P-pacman.sh
