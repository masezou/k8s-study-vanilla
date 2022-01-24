#!/usr/bin/env bash

#########################################################
# SC =local-hostpath / nfs-sc
SC=local-hostpath

NAMESPACE=genericbackup-test
PROFILE=minio-profile

#########################################################
kubectl create namespace ${NAMESPACE}
kubectl label namespace ${NAMESPACE} k10/injectKanisterSidecar=true
cat <<EOF | kubectl apply -n ${NAMESPACE} -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc
  labels:
    app: demo
    pvc: demo
spec:
  storageClassName: ${SC}
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  labels:
    app: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
      - name: demo-container
        image: alpine:3.7
        resources:
            requests:
              memory: 256Mi
              cpu: 100m
        command: ["tail"]
        args: ["-f", "/dev/null"]
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: demo-pvc
EOF
sleep 10
kubectl -n ${NAMESPACE} get pvc
kubectl -n ${NAMESPACE} get pod
kubectl -n ${NAMESPACE} wait pod -l app=demo --for condition=Ready --timeout 180s
kubectl -n ${NAMESPACE} get pvc
kubectl -n ${NAMESPACE} get pod
kubectl get pods --namespace=${NAMESPACE} | grep demo-app
cp 00-Detailed_Instruction-En.txt demodata
kubectl -n ${NAMESPACE} cp demodata \
  $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name):/data/demodata
kubectl exec --namespace=${NAMESPACE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name) -- ls -l /data

cat <<EOF > generic-backup.yaml
kind: Policy
apiVersion: config.kio.kasten.io/v1alpha1
metadata:
  name: ${NAMESPACE}-backup
  namespace: kasten-io
spec:
  comment: Generic Backup test backup policy
  frequency: "@hourly"
  retention:
    hourly: 3
  selector:
    matchExpressions:
      - key: k10.kasten.io/appNamespace
        operator: In
        values:
          - ${NAMESPACE}
  actions:
    - action: backup
      backupParameters:
        filters: {}
        profile:
          name: ${PROFILE}
          namespace: kasten-io
EOF
kubectl --namespace=kasten-io create -f generic-backup.yaml
echo "Follwoing is test data"
kubectl exec --namespace=${NAMESPACE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name) -- ls -l /data
cat >backup-run-action.yaml <<EOF
apiVersion: actions.kio.kasten.io/v1alpha1
kind: RunAction
metadata:
  generateName: run-backup-
spec:
  subject:
    kind: Policy
    name: ${NAMESPACE}-backup
    namespace: kasten-io
EOF
kubectl create -f backup-run-action.yaml 

echo "Wait for finishing and succeful BACKUP ${NAMESPACE} in Kasten Dashboard. then"
read -p "Press any key to continue... " -n1 -s

#Delete data
kubectl exec --namespace=${NAMESPACE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name) -- rm -rf /data/demodata
echo "Test Data was removed"
kubectl exec --namespace=${NAMESPACE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name) -- ls -l /data
echo "execute RESTORE ${NAMESPACE} in Kasten Dashboard. then"
read -p "Press any key to continue... " -n1 -s

echo "Verify data"

echo "Original data in this host"
md5sum demodata
echo ""
kubectl get pods --namespace=${NAMESPACE} | grep demo-app
kubectl -n ${NAMESPACE} cp \
  $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name):/data/demodeta demodata_restored
echo "Restored data which it was copoed to host"
md5sum  demodata_restored

echo "delete test namespace and backup policy"
read -p "Press any key to continue... " -n1 -s
kubectl -n kasten-io delete policy ${NAMESPACE}-backup
kubectl delete ns ${NAMESPACE}
