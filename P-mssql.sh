#!/usr/bin/env bash

#########################################################
kubectl create ns sqlserver
kubectl create secret generic mssql --from-literal=SA_PASSWORD="MyC0m9l&xP@ssw0rd" -n sqlserver
cat <<EOF | kubectl create -f -
 kind: PersistentVolumeClaim
 apiVersion: v1
 metadata:
    name: mssql-data
    namespace: sqlserver
 spec:
    accessModes:
    - ReadWriteOnce
    resources:
       requests:
          storage: 8Gi
EOF
cat <<EOF | kubectl create -f -
 apiVersion: apps/v1
 kind: Deployment
 metadata:
    name: mssql-deployment
    namespace: sqlserver
    labels:
       app: mssql
 spec:
    replicas: 1
    selector:
        matchLabels:
          app: mssql
    template:
       metadata:
          labels:
             app: mssql
       spec:
          terminationGracePeriodSeconds: 30
          hostname: mssqlinst
          securityContext:
             fsGroup: 10001
          containers:
          - name: mssql
            image: mcr.microsoft.com/mssql/server:2019-latest
            ports:
             - containerPort: 1433
            env:
             - name: MSSQL_PID
               value: "Developer"
             - name: ACCEPT_EULA
               value: "Y"
             - name: SA_PASSWORD
               valueFrom:
                secretKeyRef:
                   name: mssql
                   key: SA_PASSWORD
            volumeMounts:
             - name: mssqldb
               mountPath: /var/opt/mssql
          volumes:
             - name: mssqldb
               persistentVolumeClaim:
                claimName: mssql-data
EOF
cat <<EOF | kubectl create -f -
 apiVersion: v1
 kind: Service
 metadata:
    name: mssql-deployment
    namespace: sqlserver
 spec:
    selector:
       app: mssql
    ports:
    - protocol: TCP
      port: 1433
      targetPort: 1433
    type: LoadBalancer
EOF

