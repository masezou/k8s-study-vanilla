#!/usr/bin/env bash

CONTEXT=`kubectl config get-contexts -o=name`
CLUSTERNAME=`kubectl config get-clusters | tail -n 1`
k10multicluster setup-primary --context=${CONTEXT} --name=${CLUSTERNAME} 
cat <<EOF | kubectl apply -f -
apiVersion: auth.kio.kasten.io/v1alpha1
kind: K10ClusterRoleBinding
metadata:
  name: admin-all-clusters
  namespace: kasten-io-mc
spec:
  clusters:
  - selector: ""
  k10ClusterRole: k10-multi-cluster-admin
  subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: system:serviceaccount:kasten-io:k10-k10
EOF

# define global NFS storage
kubectl get sc | grep nfs-csi
retval12=$?
if [ ${retval12} -eq 0 ]; then
KASTENNFSPVC=kastenbackup-global-pvc
cat <<EOF | kubectl apply -n kasten-io -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
   name: ${KASTENNFSPVC}
spec:
   storageClassName: nfs-csi
   accessModes:
      - ReadWriteMany
   resources:
      requests:
         storage: 20Gi
EOF
fi

if [ -f K2-kasten-storage.sh ]; then
cp K2-kasten-storage.sh K7-kasten-storage.sh
sed -i -e "s/kasten-io/kasten-io-mc/g" K7-kasten-storage.sh
sed -i -e "s/minio-profile/minio-global-profile/g" K7-kasten-storage.sh
sed -i -e "s/miniolock-profile/miniolock-global-profile/g" K7-kasten-storage.sh
sed -i -e "s/nfs-profile/nfs-global-profile/g" K7-kasten-storage.sh
sed -i -e "s/kastenbackup-pvc/kastenbackup-global-pvc/g" K7-kasten-storage.sh
sed -i -e "s/vbr-profile/vbr-global-profileg/g" K7-kasten-storage.sh
sed -i -e '/^BUCKETNAME/d' K7-kasten-storage.sh
sed -i -e '/^MINIOLOCK_BUCKET_NAME/d' K7-kasten-storage.sh
sed -i -e '/^MCLOGINPASSWORD/i BUCKETNAME=`hostname`-global'  K7-kasten-storage.sh
sed -i -e '/^MCLOGINPASSWORD/i MINIOLOCK_BUCKET_NAME=`hostname`-lock-global'  K7-kasten-storage.sh
bash ./K7-kasten-storage.sh
rm -rf  ./K7-kasten-storage.sh
fi
if [ -f K3-kasten-vsphere.sh ]; then
cp K3-kasten-vsphere.sh K8-kasten-vsphere.sh
sed -i -e "s/kasten-io/kasten-io-mc/g" K8-kasten-vsphere.sh
sed -i -e "s/vsphere-profile/vsphere-global-profile/g" K8-kasten-vsphere.sh
bash  ./K8-kasten-vsphere.sh
rm -rf  ./K8-kasten-vsphere.sh
fi

chmod -x $0
