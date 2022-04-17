#!/usr/bin/env bash
#########################################################
MSSQLNAMESPACE=sqlserver
MSQSQLPASSWORD="MyC0m9l&xP@ssw0rd"

# SC = csi-hostpath-sc / local-hostpath / nfs-sc / nfs-csi / vsphere-sc / example-vanilla-rwo-filesystem-sc / cstor-csi-disk
SC=vsphere-sc

SAMPLEDATA=1

#REGISTRYURL=192.168.133.2:5000

#########################################################
kubectl get ns | grep ${MSSQLNAMESPACE}
retvalsvc=$?
if [ ${retvalsvc} -ne 0 ]; then

# Checking Storage Class availability
SCDEFAULT=`kubectl get sc | grep default | cut -d " " -f1`
kubectl get sc | grep ${SC}
retvalsc=$?
if [ ${retvalsc} -ne 0 ]; then
echo -e "\e[31m Switching to default storage class \e[m"
SC=${SCDEFAULT}
echo ${SC}
fi

kubectl create ns ${MSSQLNAMESPACE}
kubectl create secret generic mssql --from-literal=SA_PASSWORD=${MSQSQLPASSWORD} -n ${MSSQLNAMESPACE}
cat <<EOF | kubectl create -f -
 kind: PersistentVolumeClaim
 apiVersion: v1
 metadata:
    name: mssql-data
    namespace: ${MSSQLNAMESPACE}
 spec:
    accessModes:
    - ReadWriteOnce
    resources:
       requests:
          storage: 8Gi
    storageClassName: ${SC}
EOF
cat <<EOF | kubectl create -f -
 apiVersion: apps/v1
 kind: Deployment
 metadata:
    name: mssql-deployment
    namespace: ${MSSQLNAMESPACE}
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
    namespace: ${MSSQLNAMESPACE}
 spec:
    selector:
       app: mssql
    ports:
    - protocol: TCP
      port: 1433
      targetPort: 1433
    type: LoadBalancer
EOF
kubectl -n ${MSSQLNAMESPACE} wait pod -l app=mssql --for condition=Ready --timeout 180s
fi

EXTERNALIP=`kubectl -n ${MSSQLNAMESPACE} get service mssql-deployment | awk '{print $4}' | tail -n 1`
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
if [ ${retvalsvc} -ne 0 ]; then
if [ ! -z ${DNSDOMAINNAME} ]; then
kubectl -n ${MSSQLNAMESPACE} annotate service mssql-deployment \
    external-dns.alpha.kubernetes.io/hostname=${MSSQLNAMESPACE}.${DNSDOMAINNAME}
fi
fi

if [ ${retvalsvc} -ne 0 ]; then
if [ ${SAMPLEDATA} -eq 1 ]; then
sleep 5
kubectl exec $(kubectl -n${MSSQLNAMESPACE} get pod -l app=mssql -o custom-columns=:metadata.name) -n ${MSSQLNAMESPACE}  -- wget https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2019.bak -O /var/opt/mssql/data/AdventureWorks2019.bak
kubectl exec $(kubectl -n${MSSQLNAMESPACE} get pod -l app=mssql -o custom-columns=:metadata.name) -n ${MSSQLNAMESPACE}  -- /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P ${MSQSQLPASSWORD}  -Q "RESTORE DATABASE AdventureWorks2019 FROM  DISK = N'/var/opt/mssql/data/AdventureWorks2019.bak' WITH MOVE 'AdventureWorks2017' TO '/var/opt/mssql/data/AdventureWorks2019.mdf', MOVE 'AdventureWorks2017_Log' TO '/var/opt/mssql/data/AdventureWorks2019_Log.ldf'"

kubectl exec $(kubectl -n${MSSQLNAMESPACE} get pod -l app=mssql -o custom-columns=:metadata.name) -n ${MSSQLNAMESPACE}  -- /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P ${MSQSQLPASSWORD}  -Q "ALTER DATABASE AdventureWorks2019 SET recovery FULL SELECT CONVERT(nvarchar(50), DATABASEPROPERTYEX('AdventureWorks2019', 'recovery')) AS recovery"
fi
fi

echo ""
echo "*************************************************************************************"
echo "MSSQL Host: ${MSSQLNAMESPACE}.${DNSDOMAINNAME} / ${EXTERNALIP}"
echo "Credential: sa / ${MSQSQLPASSWORD}"
echo ""
echo "How to connect"
echo ""
echo "sqlcmd -S ${EXTERNALIP} -U sa -P \"${MSQSQLPASSWORD}\""
echo "1> select name from sys.databases;"
echo "2> go"
echo ""
if [ ${SAMPLEDATA} -eq 1 ]; then
echo ""
echo "Database: AdventureWorks2019 was imported"
fi
echo ""
