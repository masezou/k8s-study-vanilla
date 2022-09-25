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
	UBUNTUVER=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d "=" -f2)
	case ${UBUNTUVER} in
	"20.04")
		echo -e "\e[32m${UBUNTUVER} is OK. \e[m"
		;;
	"22.04")
		echo "${UBUNTUVER} is experimental."
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
		cat <<EOF >>/etc/multipath.conf
blacklist {
  devnode "^sd[a-z0-9]+"
}
EOF
		systemctl restart multipathd
		curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/master/scripts/environment_check.sh | bash

		kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
		helm repo add longhorn https://charts.longhorn.io
		helm repo update
		kubectl create namespace longhorn-system
		helm install longhorn longhorn/longhorn --namespace longhorn-system --set defaultSettings.backupTarget="s3://backupbucket@us-east-1/" --set defaultSettings.backupTargetCredentialSecret="minio-secret"
		sleep 40
		# Checking Longhorn boot up
		kubectl -n longhorn-system wait pod -l app=longhorn-manager --for condition=Ready --timeout 360s
		kubectl -n longhorn-system wait pod -l app=longhorn-conversion-webhook --for condition=Ready --timeout 360s
		kubectl -n longhorn-system wait pod -l app=longhorn-driver-deployer --for condition=Ready --timeout 360s
		kubectl -n longhorn-system wait pod -l app=longhorn-ui --for condition=Ready --timeout 360s

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
        LONGHORNMINIO=`kubectl -n longhorn-system describe deployments.apps longhorn-admission-webhook | grep "app.kubernetes.io/version" | cut -d "=" -f 2 | uniq`
		kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/${LONGHORNMINIO}/deploy/backupstores/minio-backupstore.yaml
		kubectl wait pod -l app=longhorn-test-minio --for condition=Ready --timeout 720s
		sleep 10
		LONGHRONMINIOEP_IP=$(kubectl get svc minio-service -o jsonpath="{.spec.clusterIP}")
		if [ ! -f /usr/local/bin/mc ]; then
			curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://dl.min.io/client/mc/release/linux-${ARCH}/mc
			mv mc /usr/local/bin/
			chmod +x /usr/local/bin/mc
			echo "complete -C /usr/local/bin/mc mc" >/etc/bash_completion.d/mc.sh
			/usr/local/bin/mc update
		fi
		mc alias set longhorn-minio https://${LONGHRONMINIOEP_IP}:9000 longhorn-test-access-key longhorn-test-secret-key --api "s3v4" --insecure

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
${NFSSUBPATH} 192.168.0.0/16(rw,async,no_root_squash)
${NFSSUBPATH} 172.16.0.0/12(rw,async,no_root_squash)
${NFSSUBPATH} 10.0.0.0/8(rw,async,no_root_squash)
${NFSSUBPATH} 127.0.0.1/8(rw,async,no_root_squash)
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
