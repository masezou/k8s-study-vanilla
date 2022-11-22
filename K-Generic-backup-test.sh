#!/usr/bin/env bash

#########################################################
# SC =local-path / nfs-sc
SC=local-path

NAMESPACE=genericbackup-test
PROFILE=minio-profile
TESTFILE=00-Detailed_Instruction-En.txt

#########################################################
# Clean up
rm -rf demodata* generic-backup.yaml backup-run-action.yaml

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
        image: alpine:3.17.0
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
TARGETFILE=demodata-$(date "+%Y%m%d_%H%M%S")
cp ${TESTFILE} ${TARGETFILE}
kubectl -n ${NAMESPACE} cp ${TARGETFILE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name):/data/${TARGETFILE}
kubectl exec --namespace=${NAMESPACE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name) -- ls -l /data

cat <<EOF >generic-backup.yaml
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
echo ""
echo ""
echo -e "\e[32m Follwoing is test data \e[m"
kubectl exec --namespace=${NAMESPACE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name) -- ls -l /data
echo ""
echo ""

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
rm -rf backup-run-action.yaml

echo -e "\e[32m Wait for finishing and successful BACKUP ${NAMESPACE} in Kasten Dashboard. then \e[m"
read -p "Press any key to continue... " -n1 -s

#Delete data
kubectl exec --namespace=${NAMESPACE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name) -- rm -rf /data/${TARGETFILE}
echo ""
echo ""
echo -e "\e[31m Test Data was removed \e[m"
kubectl exec --namespace=${NAMESPACE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name) -- ls -l /data
echo ""
echo ""
echo -e "\e[31m RESTORE ${NAMESPACE} in Kasten Dashboard. then  \e[m"
read -p "Press any key to continue... " -n1 -s

kubectl -n ${NAMESPACE} wait pod -l app=demo --for condition=Ready --timeout 180s
sleep 10
kubectl -n ${NAMESPACE} get pvc
echo "Wait for bonding"
sleep 20
kubectl -n ${NAMESPACE} get pod
kubectl -n ${NAMESPACE} get pvc
while [[ $(kubectl -n ${NAMESPACE} get pvc demo-pvc -o 'jsonpath={..status.phase}') != "Bound" ]]; do echo "waiting for PVC status" && sleep 1; done
echo "Verify data"
echo -e "\e[32m Original data in this host. \e[m"
echo ""
echo ""
md5sum ${TARGETFILE}
echo ""
echo ""
kubectl get pods --namespace=${NAMESPACE} | grep demo-app

echo -e "\e[31m Restored data \e[m"
kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name
kubectl exec --namespace=${NAMESPACE} $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name | grep demo-app) -- ls -l /data
echo ""
echo ""
kubectl -n ${NAMESPACE} cp $(kubectl -n ${NAMESPACE} get pod -l app=demo -o custom-columns=:metadata.name | grep demo-app):/data/${TARGETFILE} ${TARGETFILE}_restored
echo "Restored data which it was copoed to host"
echo -e "\e[31m Restored data which it was copoed to host. \e[m"
echo ""
echo ""
md5sum ${TARGETFILE}_restored
echo ""
echo ""

echo "Cleanup, it will delete test namespace and backup policy"
read -p "Press any key to continue... " -n1 -s
kubectl -n kasten-io delete policy ${NAMESPACE}-backup
kubectl delete ns ${NAMESPACE}
rm -rf demodata* generic-backup.yaml backup-run-action.yaml
echo "Test was finished."
exit 0
