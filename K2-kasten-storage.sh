#!/usr/bin/env bash

#########################################################
# Edit this section

# For VBR Repository setting. 
VBRADDRESS="VBR_ADDRESS"
VBRUSERNAME="DOMAIN\administrator"
VBRPASSWORD="VBR_PASSWORD"
VBRREPONAME="DEFAULT Backup Repository 1"

#########################################################

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

MINIOIP=${LOCALIPADDR}
MCLOGINUSER=miniologinuser
MCLOGINPASSWORD=miniologinuser
BUCKETNAME=`hostname`
MINIOLOCK_BUCKET_NAME=`hostname`-lock
MINIOLOCK_PERIOD=30d
PROTECTION_PERIOD=240h
KASTENNFSPVC=kastenbackup-pvc

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

# Immutable setting
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

# NFS Server
kubectl -n kasten-io get pvc | grep ${KASTENNFSPVC}
retval1=$?
if [ ${retval1} -eq 0 ]; then
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
if [ ${VBRADDRESS} != "VBR_ADDRESS" ]; then
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
echo ""

chmod -x ./K2-kasten-storage.sh
