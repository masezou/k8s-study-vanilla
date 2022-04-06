#!/usr/bin/env bash

#########################################################
# Edit this section

# For VBR Repository setting. 
VBRADDRESS="YOUR_VBR_ADDRESS"
VBRUSERNAME="YOUR_DOMAIN\administrator"
VBRPASSWORD="YOUR_VBR_PASSWORD"
VBRREPONAME="YOUR_DEFAULT Backup Repository 1"

# Minio Immutable setting
ERASURE_CODING=1
MINIOLOCK_PERIOD=30d
PROTECTION_PERIOD=240h

#FORCE_LOCALIP=192.168.16.2
#########################################################

if [ -z ${ERASURE_CODING} ]; then
mc admin info local | grep Pool
retvalec=$?
if [ ${retvalec} -eq 0 ]; then
ERASURE_CODING=1
else
ERASURE_CODING=0
fi
fi

#### LOCALIP (from kubectl) #########
if [ -z ${FORCE_LOCALIP} ]; then
LOCALIPADDR=`kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'`
else
LOCALIPADDR=${FORCE_LOCALIP}
fi
if [ -z ${LOCALIPADDR} ]; then
echo -e "\e[31m Local IP address setting was failed, please set FORCE_LOCALIP and re-run.  \e[m"
exit 255
else
echo ${LOCALIPADDR}
fi

MINIOBINPATH=/usr/local/bin
if [ -f ${MINIOBINPATH}/mc ]; then
MINIOIP=${LOCALIPADDR}
MCLOGINUSER=miniologinuser
MCLOGINPASSWORD=miniologinuser
BUCKETNAME=`hostname`
MINIOLOCK_BUCKET_NAME=`hostname`-lock

mc alias rm local
MINIO_ENDPOINT=https://${MINIOIP}:9000
mc alias set local ${MINIO_ENDPOINT} ${MCLOGINUSER} ${MCLOGINPASSWORD} --api S3v4

# Configure local minio setup
AWS_ACCESS_KEY_ID=` echo -n "${MCLOGINUSER}" | base64`
AWS_SECRET_ACCESS_KEY_ID=` echo -n "${MCLOGINPASSWORD}" | base64`

cat << EOF | kubectl -n kasten-io create -f -
apiVersion: v1
data:
  aws_access_key_id: ${AWS_ACCESS_KEY_ID}
  aws_secret_access_key: ${AWS_SECRET_ACCESS_KEY_ID}
kind: Secret
metadata:
  name: k10-s3-secret
  namespace: kasten-io
type: secrets.kanister.io/aws
EOF
cat <<EOF | kubectl -n kasten-io create -f -
apiVersion: config.kio.kasten.io/v1alpha1
kind: Profile
metadata:
  name: minio-profile
  namespace: kasten-io
spec:
  type: Location
  locationSpec:
    credential:
      secretType: AwsAccessKey
      secret:
        apiVersion: v1
        kind: Secret
        name: k10-s3-secret
        namespace: kasten-io
    type: ObjectStore
    objectStore:
      name: ${BUCKETNAME}
      objectStoreType: S3
      endpoint: 'https://${MINIOIP}:9000'
      skipSSLVerify: true
      region: us-east-1
EOF

# Minio immutable setting
if [ ${ERASURE_CODING} -eq 1 ]; then
mc mb --with-lock --region=us-east1 local/${MINIOLOCK_BUCKET_NAME}
mc retention set --default compliance ${MINIOLOCK_PERIOD} local/${MINIOLOCK_BUCKET_NAME}
cat <<EOF | kubectl -n kasten-io create -f -
apiVersion: config.kio.kasten.io/v1alpha1
kind: Profile
metadata:
  name: miniolock-profile
  namespace: kasten-io
spec:
  type: Location
  locationSpec:
    credential:
      secretType: AwsAccessKey
      secret:
        apiVersion: v1
        kind: Secret
        name: k10-s3-secret
        namespace: kasten-io
    type: ObjectStore
    objectStore:
      name: ${MINIOLOCK_BUCKET_NAME}
      objectStoreType: S3
      endpoint: '${MINIO_ENDPOINT}'
      skipSSLVerify: true
      region: us-east-1
      protectionPeriod: ${PROTECTION_PERIOD}
EOF
fi
fi
# NFS Storage
KASTENNFSPVC=kastenbackup-pvc
kubectl get sc | grep nfs-csi
retval3=$?
if [ ${retval3} -eq 0 ]; then
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
cat <<EOF | kubectl -n kasten-io create -f -
apiVersion: config.kio.kasten.io/v1alpha1
kind: Profile
metadata:
  name: nfs-profile
  namespace: kasten-io
spec:
  type: Location
  locationSpec:
    type: FileStore
    fileStore:
      claimName: ${KASTENNFSPVC}
EOF
fi

# Configure vbr setup
if [ ${VBRADDRESS} != "YOUR_VBR_ADDRESS" ]; then
kubectl get sc | grep csi.vsphere.vmware.com
retvalvbr=$?
if [ ${retvalvbr} -eq 0 ]; then
VBRUSER=` echo -n "${VBRUSERNAME}" | base64`
VBRPASS=` echo -n "${VBRPASSWORD}" | base64`

cat << EOF | kubectl -n kasten-io create -f -
apiVersion: v1
data:
  vbr_password:  ${VBRPASS}
  vbr_user: ${VBRUSER}
kind: Secret
metadata:
  name: k10-vbr-secret
  namespace: kasten-io
type: Opaque

EOF
cat <<EOF | kubectl -n kasten-io create -f -
apiVersion: config.kio.kasten.io/v1alpha1
kind: Profile
metadata:
  name: vbr-profile
  namespace: kasten-io
spec:
  type: Location
  locationSpec:
    credential:
      secretType: VBRKey
      secret:
        apiVersion: v1
        kind: Secret
        name: k10-vbr-secret
        namespace: kasten-io
    type: VBR
    vbr:
      repoName: ${VBRREPONAME}
      serverAddress: ${VBRADDRESS}
      serverPort: 9419
      skipSSLVerify: true
EOF
fi
fi


echo "*************************************************************************************"
echo "Kasten Backup storages were configured"
kubectl -n kasten-io get profiles
echo ""
echo ""
if [ ${ERASURE_CODING} -eq 1 ]; then
echo -e "\e[32m MINIO Lock bucket and polocy were created. \e[m"
else
echo -e "\e[31m MINIO Lock bucket and polocy were not created due to not having your MINIO compatibility.\e[m"
fi
chmod -x $0
