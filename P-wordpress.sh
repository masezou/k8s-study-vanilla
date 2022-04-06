#!/usr/bin/env bash

#########################################################
# Offline Install
#OFFLINE=1
#REGISTRYHOST=192.168.133.2
#REGISTRYURL=${REGISTRYHOST}:5000

# namespace. namespace will be used with hostname
NAMESPACE=blog1

# SC = csi-hostpath-sc / local-hostpath / nfs-sc / nfs-csi / vsphere-sc / example-vanilla-rwo-filesystem-sc / cstor-csi-disk
SC=vsphere-sc

#########################################################

if [ -z ${OFFLINE} ]; then
OFFLINE=0
fi

DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
WPHOST=${NAMESPACE}

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
if [ ! -f /usr/local/bin/helm ]; then
curl -s -O https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
bash ./get-helm-3
helm version
rm get-helm-3
helm completion bash > /etc/bash_completion.d/helm
source /etc/bash_completion.d/helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
fi
fi

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
kubectl create namespace ${NAMESPACE}
mkdir ${NAMESPACE}
cd  ${NAMESPACE}

if [ ${OFFLINE} -eq 1 ]; then
if [ -z ${REGISTRYURL} ]; then
#REGISTRYHOST=`kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'`
#REGISTRYURL=${REGISTRYHOST}:5000
ls -1 /etc/containerd/certs.d/ | grep -v docker.io
retchk=$?
if [ ${retchk} -ne 0 ]; then
echo -e "\e[31m Registry is not configured on this host. Exit. \e[m"
exit 255
fi
REGISTRYURL=`ls -1 /etc/containerd/certs.d/ | grep -v docker.io`
fi
#helm fetch bitnami/mysql
helm fetch bitnami/mysql --version=8.8.27
MYSQLCHART=`ls mysql-*.tgz`
fi

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

if [ ${OFFLINE} -eq 1 ]; then
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
      - image: ${REGISTRYURL}/library/wordpress:4.8-apache
        imagePullPolicy: Always
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

else

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
        imagePullPolicy: IfNotPresent
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
fi
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

if [ ${OFFLINE} -eq 1 ]; then
if [ ${SC} = csi-hostpath-sc ]; then
helm install mysql-release ${MYSQLCHART}  -n ${NAMESPACE} --set volumePermissions.enabled=true --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRYURL}
else
helm install mysql-release ${MYSQLCHART}  -n ${NAMESPACE} --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRYURL}
fi
else
if [ ${SC} = csi-hostpath-sc ]; then
helm install mysql-release bitnami/mysql -n ${NAMESPACE} --set volumePermissions.enabled=true --set global.storageClass=${SC}
else
helm install mysql-release bitnami/mysql -n ${NAMESPACE} --set global.storageClass=${SC}
fi
fi
sleep 5
kubectl get pod,pvc -n ${NAMESPACE} 
echo "Initial sleep 30s"
sleep 30
kubectl -n ${NAMESPACE} get pod,pvc
while [ "$(kubectl get pod -n ${NAMESPACE} mysql-release-0 --output="jsonpath={.status.containerStatuses[*].ready}" | cut -d' ' -f2)" != "true" ]; do
	echo "Deploying Stateful MySQL, Please wait...."
    kubectl get pod,pvc -n ${NAMESPACE} 
	sleep 30
done
    kubectl get pod,pvc -n ${NAMESPACE} 
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

kubectl -n ${NAMESPACE} annotate service wordpress \
    external-dns.alpha.kubernetes.io/hostname=${WPHOST}.${DNSDOMAINNAME}
kubectl -n blog1 wait pod -l app=wordpress --for condition=Ready --timeout 180s

sleep 30
host ${WPHOST}.${DNSDOMAINNAME}. ${DNSHOSTIP}
retvaldns=$?
echo ""
echo "*************************************************************************************"
if [ ${OFFLINE} -eq 1 ]; then
kubectl images -n ${NAMESPACE}
fi 
echo "Next Step"
echo "Confirm wordpress pod and mysql pod are running with kubectl get pod -A"
echo "Open http://${EXTERNALIP}"
if [ ${retvaldns} -eq 0 ]; then 
echo "or"
echo "Open http://${WPHOST}.${DNSDOMAINNAME}/wp-admin/install.php"
fi
echo ""
