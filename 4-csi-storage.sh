#!/usr/bin/env bash
echo -e "\e[32mStarting $0 ....\e[m"
#########################################################

# Specify NFS storage location path
# Localhost server
NFSSC=1
NFSCSI=0
# NFSSVER=1:local 0:external
NFSSVR=1
NFSPATH=/disk/nfs_csi
NFSSUBPATH=/disk/nfs_sub
# External nfs server
EXNFSSVRIPADDR=192.168.10.4
EXNFSPATH=/k8s_share
EXNFSSUBPATH=/k8s_sharedyn

SMBSC=0
SMBHOST=192.168.10.4
SMBSHARE=/k8s_smb

LONGHORN=1

#FORCE_LOCALIP=192.168.16.2

# Experimental

SYNOLOGY=0
SYNOLOGYHOST="YOUR_SYNOLOGY_HOST"
SYNOLOGYPORT="5001"
SYNOLOGYHTTPS="true"
SYNOLOGYUSERNAME="YOUR_SYNOLOGY_USER"
SYNOLOGYPASSWORD="YOUR_SYNOLOGY_PASSWORD"

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
		curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/master/scripts/environment_check.sh | bash

		kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
		LONGHORNVER=1.3.1
		kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORNVER}/deploy/longhorn.yaml
		sleep 40
		# Checking Longhorn boot up
		kubectl -n longhorn-system wait pod -l app=longhorn-manager --for condition=Ready --timeout 360s
		kubectl -n longhorn-system wait pod -l app=longhorn-conversion-webhook --for condition=Ready --timeout 360s
		kubectl -n longhorn-system wait pod -l app=longhorn-driver-deployer --for condition=Ready --timeout 360s
		kubectl wait pod -l app=longhorn-test-minio --for condition=Ready --timeout 720s
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

		kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORNVER}/deploy/backupstores/minio-backupstore.yaml
		kubectl wait pod -l app=longhorn-test-minio --for condition=Ready
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
		# NFS v4
		#kubectl apply -f https://github.com/longhorn/longhorn/blob/v1.2.4/deploy/backupstores/nfs-backupstore.yaml

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
			mkdir -p ${NFSPATH}
			chmod -R 1777 ${NFSPATH}
			mkdir -p ${NFSSUBPATH}
			chmod -R 1777 ${NFSSUBPATH}
			cat <<EOF >>/etc/exports
${NFSPATH} 192.168.0.0/16(rw,async,no_root_squash)
${NFSPATH} 172.16.0.0/12(rw,async,no_root_squash)
${NFSPATH} 10.0.0.0/8(rw,async,no_root_squash)
${NFSPATH} 127.0.0.1/8(rw,async,no_root_squash)
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

	if [ ${NFSCSI} -eq 1 ]; then
		# Install NFS-CSI driver for single node
		#kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/rbac-csi-nfs-controller.yaml
		#kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/csi-nfs-driverinfo.yaml
		#kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/csi-nfs-controller.yaml
		NFSCSIVER=4.1.0
		curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v${NFSCSIVER}/deploy/install-driver.sh | bash -s v${NFSCSIVER} --
		kubectl -n kube-system patch deployment csi-nfs-controller -p '{"spec":{"replicas": 1}}'
		sleep 2
		kubectl -n kube-system get deployments.apps csi-nfs-controller
		kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/csi-nfs-node.yaml
		while [ "$(kubectl -n kube-system get deployments.apps csi-nfs-controller --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
			echo "Deploying CSI-NFS controller Please wait...."
			kubectl -n kube-system get deployments.apps csi-nfs-controller
			sleep 30
		done
		kubectl -n kube-system get deployments.apps csi-nfs-controller
		kubectl -n kube-system wait pod -l app=csi-nfs-node --for condition=Ready --timeout 180s

		curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/example/storageclass-nfs.yaml
		if [ ${NFSSVR} -eq 1 ]; then
			sed -i -e "s/nfs-server.default.svc.cluster.local/${LOCALIPADDR}/g" storageclass-nfs.yaml
			sed -i -e "s@share: /@share: ${NFSPATH}@g" storageclass-nfs.yaml
		else
			if [ ! -z ${EXNFSSVRIPADDR} ]; then
				sed -i -e "s/nfs-server.default.svc.cluster.local/${EXNFSSVRIPADDR}/g" storageclass-nfs.yaml
				sed -i -e "s@share: /@share: ${EXNFSPATH}@g" storageclass-nfs.yaml
				sed -i -e "s/4.1/3/g" storageclass-nfs.yaml
			fi
		fi
		kubectl create -f storageclass-nfs.yaml
		#kubectl create secret generic mount-options --from-literal mountOptions="nfsvers=3,hard"
		rm -rf storageclass-nfs.yaml
		kubectl patch storageclass nfs-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
		kubectl delete CSIDriver nfs.csi.k8s.io
		cat <<EOF | kubectl create -f -
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: nfs.csi.k8s.io
spec:
  attachRequired: false
  volumeLifecycleModes:
    - Persistent
  fsGroupPolicy: File
EOF
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

if [ ${SMBSC} -eq 1 ]; then
	echo ${SMBHOST}
	echo ${SMBSHARE}
fi

# Install Synology CSI (Experimental)
if [ ${SYNOLOGY} -eq 1 ]; then
	git clone --depth 1 https://github.com/kubernetes-csi/external-snapshotter
	cd external-snapshotter
	kubectl kustomize client/config/crd | kubectl create -f -
	kubectl -n kube-system kustomize deploy/kubernetes/snapshot-controller | kubectl create -f -
	cd ..
	apt -y install make golang-go smbclient cifs-utils
	git clone --depth 1 git@github.com:SynologyOpenSource/synology-csi.git
	cd synology-csi
	cat <<EOF >config/client-info.yml
---
clients:
  - host: ${SYNOLOGYHOST}
    port: ${SYNOLOGYPORT}
    https: ${SYNOLOGYHTTPS}
    username: ${SYNOLOGYUSERNAME}
    password: ${SYNOLOGYPASSWORD}
EOF

	./scripts/deploy.sh install --all
	cd ..
	kubectl get pods -n synology-csi
	kubectl get node -o wide | grep v1.19 >/dev/null
	retvalkube19=$?
	if [ ${retvalkube19} -eq 0 ]; then
		KUBEVER=v1.19
	else
		KUBEVER=v1.20
	fi
	kubectl apply -f deploy/kubernetes/${KUBEVER}/storage-class.yml
	kubectl apply -f deploy/kubernetes/${KUBEVER}/snapshotter/volume-snapshot-class.yml
	cat <<EOF | kubectl apply -n synology-csi -f -
apiVersion: v1
kind: Secret
metadata:
  name: cifs-csi-credentials
  namespace: synology-csi
type: Opaque
stringData:
  username: ${SYNOLOGYUSERNAME}
  password: ${SYNOLOGYPASSWORD}
EOF
	cat <<EOF | kubectl apply -n synology-csi -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: synostorage-smb
provisioner: csi.san.synology.com
parameters:
  protocol: "smb"
  dsm: '${SYNOLOGYHOST}'
  location: '/volume1'
  csi.storage.k8s.io/node-stage-secret-name: "cifs-csi-credentials"
  csi.storage.k8s.io/node-stage-secret-namespace: "synology-csi"
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF
	kubectl -n synology-csi wait pod -l app=synology-csi-controller --for condition=Ready
	kubectl -n synology-csi wait pod -l app=synology-csi-node --for condition=Ready
	kubectl -n synology-csi wait pod -l app=synology-csi-snapshotter --for condition=Ready
fi

kubectl -n openebs wait pod -l app=cstor-pool --for condition=Ready

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
