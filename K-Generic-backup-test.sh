#!/usr/bin/env bash

#########################################################

SC=local-hostpath

#########################################################
kubectl create namespace genericbackup-test
kubectl label namespace genericbackup-test k10/injectKanisterSidecar=true
cat <<EOF | kubectl apply -n genericbackup-test -f -
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
kubectl get pods --namespace=genericbackup-test | grep demo-app
cp 00-Detailed_Instruction-En.txt demodata
kubectl -n genericbackup-test cp demodata \
  $(kubectl -n genericbackup-test get pod -l app=demo -o custom-columns=:metadata.name):/data/demodeta
kubectl exec --namespace=genericbackup-test $(kubectl -n genericbackup-test get pod -l app=demo -o custom-columns=:metadata.name) -- ls -l /data


echo "execute BACKUP in Kasten Dashboard. then \n"
read -p "Press any key to continue... " -n1 -s

#Delete data
kubectl exec --namespace=genericbackup-test $(kubectl -n genericbackup-test get pod -l app=demo -o custom-columns=:metadata.name) -- rm -rf /data/demodata

echo "execute RESTORE in Kasten Dashboard. then \n"
read -p "Press any key to continue... " -n1 -s

echo "Verify data"

md5sum demodata
kubectl get pods --namespace=genericbackup-test | grep demo-app
kubectl -n genericbackup-test cp \
  $(kubectl -n genericbackup-test get pod -l app=demo -o custom-columns=:metadata.name):/data/demodeta demodata_restored
md5sum  demodata_restored
