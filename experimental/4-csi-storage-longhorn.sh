#!/usr/bin/env bash

#########################################################
### UID Check ###
if [ ${EUID:-${UID}} != 0 ]; then
    echo "This script must be run as root"
    exit 1
else
    echo "I am root user."
fi

### Distribution Check ###
lsb_release -d | grep Ubuntu | grep 20.04
DISTVER=$?
if [ ${DISTVER} = 1 ]; then
    echo "only supports Ubuntu 20.04 server"
    exit 1
else
    echo "Ubuntu 20.04=OK"
fi

### Install command check ####
if type "kubectl" > /dev/null 2>&1
then
    echo "kubectl was already installed"
else
    echo "kubectl was not found. Please install kubectl and re-run"
    exit 255
fi

#### LOCALIP #########
ip address show ens160 >/dev/null
retval=$?
if [ ${retval} -eq 0 ]; then
        LOCALIPADDR=`ip -f inet -o addr show ens160 |cut -d\  -f 7 | cut -d/ -f 1`
else
  ip address show ens192 >/dev/null
  retval2=$?
  if [ ${retval2} -eq 0 ]; then
        LOCALIPADDR=`ip -f inet -o addr show ens192 |cut -d\  -f 7 | cut -d/ -f 1`
  else
        LOCALIPADDR=`ip -f inet -o addr show eth0 |cut -d\  -f 7 | cut -d/ -f 1`
  fi
fi
echo ${LOCALIPADDR}

BASEPWD=`pwd`

SNAPSHOTTER_VERSION=v4.2.1

# Apply VolumeSnapshot CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAPSHOTTER_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAPSHOTTER_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAPSHOTTER_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# Create Snapshot Controller
kubectl -n kube-system apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAPSHOTTER_VERSION}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl -n kube-system apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAPSHOTTER_VERSION}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

#Install longhorn
LONGHORNVER="1.2.2"
#Pre-flight check
apt -y install open-iscsi nfs-common
curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORNVER}/scripts/environment_check.sh | bash

kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORNVER}/deploy/longhorn.yaml

sleep 120

USER=admin; PASSWORD=Password00; echo "${USER}:$(openssl passwd -stdin -apr1 <<< ${PASSWORD})" >> auth
kubectl -n longhorn-system create secret generic basic-auth --from-file=auth
cat <<EOF | kubectl -n longhorn-system apply  -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ingress
  namespace: longhorn-system
  annotations:
    # type of authentication
    nginx.ingress.kubernetes.io/auth-type: basic
    # prevent the controller from redirecting (308) to HTTPS
    nginx.ingress.kubernetes.io/ssl-redirect: 'false'
    # name of the secret that contains the user/password definitions
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    # message to display with an appropriate context why the authentication is required
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required '
    # custom max body size for file uploading like backing image uploading
    nginx.ingress.kubernetes.io/proxy-body-size: 10000m
spec:
  rules:
  - http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: longhorn-frontend
            port:
              number: 80
EOF
kubectl -n longhorn-system  get ingress

cat <<EOF | kubectl apply  -f -
kind: VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
metadata:
  name: longhorn
driver: driver.longhorn.io
deletionPolicy: Delete
EOF

##Install NFS-CSI driver
apt -y install nfs-kernel-server
apt clean
mkdir -p /disk/k8s_share
chmod -R 1777 /disk/k8s_share
cat << EOF >> /etc/exports
/disk/k8s_share 192.168.0.0/16(rw,async,no_root_squash)
/disk/k8s_share 172.16.0.0/12(rw,async,no_root_squash)
/disk/k8s_share 10.0.0.0/8(rw,async,no_root_squash)
/disk/k8s_share 127.0.0.1/8(rw,async,no_root_squash)
EOF
systemctl restart nfs-server
systemctl enable nfs-server
showmount -e
NFSPATH=/disk/k8s_share
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/install-driver.sh | bash -s master --
curl -OL  https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/example/storageclass-nfs.yaml
sed -i -e "s/nfs-server.default.svc.cluster.local/${LOCALIPADDR}/g" storageclass-nfs.yaml
sed -i -e "s@share: /@share: ${NFSPATH}@g" storageclass-nfs.yaml
kubectl create -f storageclass-nfs.yaml
rm -rf storageclass-nfs.yaml
kubectl patch storageclass nfs-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl -n kube-system get pod -o wide -l app=csi-nfs-controller
kubectl -n kube-system get pod -o wide -l app=csi-nfs-node
kubectl delete CSIDriver nfs.csi.k8s.io
cat <<EOF | kubectl create -f -
apiVersion: storage.k8s.io/v1beta1
kind: CSIDriver
metadata:
  name: nfs.csi.k8s.io
spec:
  attachRequired: false
  volumeLifecycleModes:
    - Persistent
  fsGroupPolicy: File
EOF


echo ""
echo "*************************************************************************************"
echo "CSI storage was created"
echo "kubectl get sc"
echo ""
echo "kubernetes deployment  without vSphere CSI driver was successfully. The environment will be fully functional."
echo ""
echo "If you want to use vSphere CSI Driver, run ./5-csi-vsphere.sh"
echo ""

cd ${BASEPWD}
chmod -x ./4-csi-storage.sh
