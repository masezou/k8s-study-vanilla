#!/usr/bin/env bash

### Install command check ####
if type "kubectl" > /dev/null 2>&1
then
    echo "kubectl was already installed"
else
    echo "kubectl was not found. Please install kubectl and re-run"
    exit 255
fi

if type "helm" > /dev/null 2>&1
then
    echo "helm was already installed"
else
    echo "helm was not found. Please install helm and re-run"
    exit 255
fi

NAMESPACE=wordpress-sample
SC=vsphere-sc

kubectl create namespace ${NAMESPACE}
mkdir ${NAMESPACE}
cd  ${NAMESPACE}

cat << EOF > wordpress-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wp-pv-claim
  labels:
    app: wordpress
    tier: wordpress
spec:
  storageClassName: ${SC}
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF
cat << EOF > wordpress.yaml
apiVersion: apps/v1 # for versions before 1.9.0 use apps/v1beta2
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: frontend
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: frontend
    spec:
      containers:
      - image: wordpress:4.8-apache
        name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql-release
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
              secretKeyRef:
                name: mysql-release
                key: mysql-root-password
        ports:
        - containerPort: 80
          name: wordpress
        volumeMounts:
        - name: wordpress-persistent-storage
          mountPath: /var/www/html
      volumes:
      - name: wordpress-persistent-storage
        persistentVolumeClaim:
          claimName: wp-pv-claim
EOF
cat << EOF > wordpress-service.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: wordpress
  name: wordpress
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  selector:
    app: wordpress
EOF

helm repo add bitnami https://charts.bitnami.com/bitnami
if [ ${SC} = csi-hostpath-sc ]; then
helm install mysql-release bitnami/mysql -n ${NAMESPACE} --set volumePermissions.enabled=true --set global.storageClass=${SC}
else
helm install mysql-release bitnami/mysql -n ${NAMESPACE} --set global.storageClass=${SC}
fi
while [ "$(kubectl get pod -n ${NAMESPACE} mysql-release-0 --output="jsonpath={.status.containerStatuses[*].ready}" | cut -d' ' -f2)" != "true" ]; do
	echo "Deploying Stateful MySQL, Please wait...."
	sleep 30
done
kubectl create -f wordpress-pvc.yaml -n ${NAMESPACE}
kubectl get pvc,pv
kubectl create -f wordpress.yaml -n ${NAMESPACE}
kubectl get pod -l app=wordpress -n ${NAMESPACE}
kubectl create -f wordpress-service.yaml -n ${NAMESPACE}
kubectl label statefulset mysql-release  app=wordpress -n ${NAMESPACE}
kubectl get svc -l app=wordpress -n ${NAMESPACE}
kubectl get pod -n ${NAMESPACE}
cd ..

mv ${NAMESPACE} ${NAMESPACE}-`date "+%Y%m%d_%H%M%S"`
EXTERNALIP=`kubectl -n ${NAMESPACE} get service wordpress |awk '{print $4}' | tail -n 1`

echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "Confirm wordpress pod and mysql pod are running with kubectl get pod -A"
echo "Open http://${EXTERNALIP}"

