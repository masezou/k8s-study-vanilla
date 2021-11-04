#!/usr/bin/env bash

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


MINIOIPi=${LOCALIPADDR}
MINIO_ROOT_USER=minioadminuser
MINIO_ROOT_PASSWORD=minioadminuser
BUCKETNAME=`hostname`
KASTENNFSPVC=kastenbackup-pvc


mc alias rm local
MINIO_ENDPOINT=https://${MINIOIP}:9000
mc alias set local ${MINIO_ENDPOINT} ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} --api S3v4

# Configure local minio setup
AWS_ACCESS_KEY_ID=` echo -n "${MINIO_ROOT_USER}" | base64`
AWS_SECRET_ACCESS_KEY_ID=` echo -n "${MINIO_ROOT_PASSWORD}" | base64`

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

sleep 10

echo ""
echo "Kasten Backup storages were configured"
echo ""

chmod -x ./K2-kasten-storage.sh
