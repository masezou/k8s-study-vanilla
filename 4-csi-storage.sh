#!/usr/bin/env bash
echo -e "\e[32mStarting $0 ....\e[m"
#########################################################

# Specify NFS storage location path
# Localhost server
NFSSC=1
# NFSSVER=1:local 0:external
NFSSVR=1
NFSSUBPATH=/disk/nfs_sub
# External nfs server
EXNFSSVRIPADDR=192.168.10.4
EXNFSPATH=/k8s_share
EXNFSSUBPATH=/k8s_sharedyn

LONGHORN=1

#FORCE_LOCALIP=192.168.16.2

#########################################################
if [ ${NFSSVR} -eq 1 ]; then
	### UID Check ###
	if [ ${EUID:-${UID}} != 0 ]; then
		echo "This script must be run as root"
		exit 1
	else
		echo "I am root user."
	fi
	# HOSTNAME check
	ping -c 3 $(hostname)
	retvalping=$?
	if [ ${retvalping} -ne 0 ]; then
		echo -e "\e[31m HOSTNAME was not configured correctly. \e[m"
		exit 255
	fi

	### Distribution Check ###
	UBUNTUVER=$(lsb_release -rs)
	case ${UBUNTUVER} in
	"20.04")
		echo -e "\e[32m${UBUNTUVER} is OK. \e[m"
		;;
	"22.04")
		echo "${UBUNTUVER} is OK.."
		#exit 255
		;;
	*)
		echo -e "\e[31m${UBUNTUVER} is NG. \e[m"
		exit 255
		;;
	esac
	#### LOCALIP (from kubectl) #########
	if [ -z ${FORCE_LOCALIP} ]; then
		LOCALIPADDR=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
	else
		LOCALIPADDR=${FORCE_LOCALIP}
	fi
	if [ -z ${LOCALIPADDR} ]; then
		echo -e "\e[31m Local IP address setting was failed, please set FORCE_LOCALIP and re-run.  \e[m"
		exit 255
	else
		echo ${LOCALIPADDR}
	fi
fi

### Install command check ####
if type "kubectl" >/dev/null 2>&1; then
	echo "kubectl was already installed"
else
	echo "kubectl was not found. Please install kubectl and re-run"
	exit 255
fi

### Cluster check ####
kubectl get pod
retavalcluser=$?
if [ ${retavalcluser} -ne 0 ]; then
	echo -e "\e[31m Kubernetes cluster is not found. \e[m"
	exit 255
fi

BASEPWD=$(pwd)
source /etc/profile

kubectl get node | grep "NotReady"
retvalstatus=$?
if [ ${retvalstatus} -eq 0 ]; then
	echo -e "\e[31m CNI is not configured. exit. \e[m"
	exit 255
fi

kubectl get sc | grep local-path
retvallocalpath=$?
if [ ${retvallocalpath} -ne 0 ]; then
	# Rancher local driver (Not CSI Storage)
	kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
fi

if [ ${LONGHORN} -eq 1 ]; then
	kubectl get sc | grep longhorn
	retvallonghorn=$?
	if [ ${retvallonghorn} -ne 0 ]; then
		SNAPSHOTTER_VERSION=5.0.1
		# Apply VolumeSnapshot CRDs
		kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
		kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
		kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
		# Create Snapshot Controller
		kubectl -n kube-system apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
		kubectl -n kube-system apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v${SNAPSHOTTER_VERSION}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml
		apt -y install jq nfs-common
		systemctl stop multipathd && systemctl disable multipathd
		curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/master/scripts/environment_check.sh | bash

		kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
		helm repo add longhorn https://charts.longhorn.io
		helm repo update
		kubectl create namespace longhorn-system
		MCLOGINUSER=$(grep MCLOGINUSER= ./0-minio.sh | head -n 1 | cut -d "=" -f 2)
		MCLOGINPASSWORD=$(grep MCLOGINPASSWORD= 0-minio.sh | head -n 1 | head -n 1 | cut -d "=" -f 2)
		DNSDOMAINNAME=$(kubectl -n external-dns get deployments.apps --output="jsonpath={.items[*].spec.template.spec.containers }" | jq | grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1)
		MINIO_ENDPOINT="https://minio.${DNSDOMAINNAME}:9000"
		MINIOCERTDIR=/root/.minio/certs
		LONGHORNBUCKET=$(hostname)-longhorn
		mc --insecure mb local/${LONGHORNBUCKET}
		helm install longhorn longhorn/longhorn --namespace longhorn-system --set defaultSettings.backupTarget="s3://${LONGHORNBUCKET}@us-east-1/" --set defaultSettings.backupTargetCredentialSecret="minio-secret-local"
		sleep 40
		# Checking Longhorn boot up
		kubectl -n longhorn-system wait pod -l app=longhorn-manager --for condition=Ready --timeout 360s
		kubectl -n longhorn-system wait pod -l app=longhorn-conversion-webhook --for condition=Ready --timeout 360s
		kubectl -n longhorn-system wait pod -l app=longhorn-driver-deployer --for condition=Ready --timeout 360s
		kubectl -n longhorn-system wait pod -l app=longhorn-ui --for condition=Ready --timeout 360s
        kubectl -n longhorn-system wait pod -l app=csi-provisioner --for condition=Ready --timeout 360s
		cat <<EOF | kubectl apply -f -
kind: VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
metadata:
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
  name: longhorn
driver: driver.longhorn.io
deletionPolicy: Delete
EOF
		AWS_ENDPOINTS=$(echo -n ${MINIO_ENDPOINT} | base64)
		AWS_ACCESS_KEY_ID=$(echo -n ${MCLOGINUSER} | base64)
		AWS_SECRET_ACCESS_KEY=$(echo -n ${MCLOGINPASSWORD} | base64)
		AWS_CERT=$(cat ${MINIOCERTDIR}/CAs/rootCA.pem | base64 | tr -d "\n")
		cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret-local
  namespace: longhorn-system
type: Opaque
data:
  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
  AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
  AWS_ENDPOINTS: ${AWS_ENDPOINTS}
  AWS_CERT: ${AWS_CERT}
EOF
		sleep 10

		kubectl patch storageclass longhorn \
			-p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

		kubectl -n longhorn-system patch svc longhorn-frontend -p '{"spec":{"type": "LoadBalancer"}}'
		LONGHORNDB_EXTERNALIP=$(kubectl -n longhorn-system get svc longhorn-frontend -o jsonpath="{.status.loadBalancer.ingress[*].ip}")
	else
		echo "Longhorn is already installed. skip...."
	fi
fi

if [ ${NFSSC} -eq 1 ]; then
	##Install local NFS Server
	if [ ${NFSSVR} -eq 1 ]; then
		kubectl get sc | grep nfs
		retvalnfssc=$?
		if [ ${retvalnfssc} -ne 0 ]; then
			apt -y install nfs-kernel-server
			apt -y autoremove
			apt clean
			mkdir -p ${NFSSUBPATH}
			chmod -R 1777 ${NFSSUBPATH}
			cat <<EOF >>/etc/exports
${NFSSUBPATH} 192.168.0.0/16(rw,async,no_root_squash,no_subtree_check)
${NFSSUBPATH} 172.16.0.0/12(rw,async,no_root_squash,no_subtree_check)
${NFSSUBPATH} 10.0.0.0/8(rw,async,no_root_squash,no_subtree_check)
${NFSSUBPATH} 127.0.0.1/8(rw,async,no_root_squash,no_subtree_check)
EOF

			systemctl restart nfs-server
			systemctl enable nfs-server
			showmount -e
		fi
	fi

	# Install NFS-SUB
	kubectl create namespace nfs-subdir
	helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
	helm repo update
	if [ ${NFSSVR} -eq 1 ]; then
		helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner -n nfs-subdir \
			--set nfs.server=${LOCALIPADDR} \
			--set nfs.path=${NFSSUBPATH} \
			--set storageClass.name=nfs-sc
	else
		if [ ! -z ${EXNFSSVRIPADDR} ]; then
			helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner -n nfs-subdir \
				--set nfs.server=${EXNFSSVRIPADDR} \
				--set nfs.path=${EXNFSSUBPATH} \
				--set storageClass.name=nfs-sc
		fi
	fi
fi

echo ""
echo "*************************************************************************************"
echo "CSI storage was created"
echo "kubectl get sc"
kubectl get sc
echo ""
echo "kubernetes deployment without vSphere CSI driver was successfully. The environment will be functional."
echo ""
echo -e "\e[32m If you want to use vSphere CSI Driver on ESX/vCenter environment, run ./5-csi-vsphere.sh \e[m"
echo ""

cd ${BASEPWD}
chmod -x $0
ls
