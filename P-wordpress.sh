#!/usr/bin/env bash
# Copyright (c) 2022 masezou. All rights reserved.
#########################################################
# Force Online Install
#FORCE_ONLINE=1

# namespace. namespace will be used with hostname
WPNAMESPACE=blog1
# SC = csi-hostpath-sc / local-hostpath / local-path / nfs-sc / nfs-csi / vsphere-sc / example-vanilla-rwo-filesystem-sc / cstor-csi-disk / longhorn / rook-ceph-block / rook-cephfs / synostorage / synostorage-smb
SC=vsphere-sc

#REGISTRYURL=192.168.133.2:5000

#########################################################
kubectl get ns | grep ${WPNAMESPACE}
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

if [ -z ${REGISTRYURL} ]; then
REGISTRYHOST=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_host}'`
REIGSTRYPORT=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_port}'`
REGISTRYURL=${REGISTRYHOST}:${REIGSTRYPORT}
curl -s  -X GET http://${REGISTRYURL}/v2/_catalog |grep wordpress
retvalcheck=$?
if [ ${retvalcheck} -eq 0 ]; then
  ONLINE=0
  else
  ONLINE=1
fi
if [ ! -z ${FORCE_ONLINE} ] ; then
ONLINE=1
fi
fi


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
kubectl create namespace ${WPNAMESPACE}
mkdir ${WPNAMESPACE}
cd  ${WPNAMESPACE}


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

if [ ${ONLINE} -eq 0 ]; then
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

if [ ${ONLINE} -eq 0 ]; then
#helm fetch bitnami/mysql
helm fetch bitnami/mysql --version=8.8.27
MYSQLCHART=`ls mysql-*.tgz`
if [ ${SC} = csi-hostpath-sc ]; then
helm install mysql-release ${MYSQLCHART}  -n ${WPNAMESPACE} --set volumePermissions.enabled=true --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRYURL}
else
helm install mysql-release ${MYSQLCHART}  -n ${WPNAMESPACE} --set global.storageClass=${SC} --set global.imageRegistry=${REGISTRYURL}
fi
else
if [ ${SC} = csi-hostpath-sc ]; then
helm install mysql-release bitnami/mysql -n ${WPNAMESPACE} --set volumePermissions.enabled=true --set global.storageClass=${SC}
else
helm install mysql-release bitnami/mysql -n ${WPNAMESPACE} --set global.storageClass=${SC}
fi
fi
sleep 5
kubectl get pod,pvc -n ${WPNAMESPACE} 
echo "Initial sleep 30s"
sleep 30
kubectl -n ${WPNAMESPACE} get pod,pvc
while [ "$(kubectl get pod -n ${WPNAMESPACE} mysql-release-0 --output="jsonpath={.status.containerStatuses[*].ready}" | cut -d' ' -f2)" != "true" ]; do
	echo "Deploying Stateful MySQL, Please wait...."
    kubectl get pod,pvc -n ${WPNAMESPACE} 
	sleep 30
done
    kubectl get pod,pvc -n ${WPNAMESPACE} 
kubectl create -f wordpress-pvc.yaml -n ${WPNAMESPACE}
kubectl get pvc,pv -n ${WPNAMESPACE}
kubectl create -f wordpress.yaml -n ${WPNAMESPACE}
kubectl get pod -l app=wordpress -n ${WPNAMESPACE}
kubectl create -f wordpress-service.yaml -n ${WPNAMESPACE}
kubectl label statefulset mysql-release  app=wordpress -n ${WPNAMESPACE}
kubectl get svc -l app=wordpress -n ${WPNAMESPACE}
kubectl get pod -n ${WPNAMESPACE}
cd ..
fi
mv ${WPNAMESPACE} ${WPNAMESPACE}-`date "+%Y%m%d_%H%M%S"`
EXTERNALIP=`kubectl -n ${WPNAMESPACE} get service wordpress -o jsonpath="{.status.loadBalancer.ingress[*].ip}"`

WPHOST=${WPNAMESPACE}
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
if [ ${retvalsvc} -ne 0 ]; then
if [ ! -z ${DNSDOMAINNAME} ]; then
kubectl -n ${WPNAMESPACE} annotate service wordpress \
    external-dns.alpha.kubernetes.io/hostname=${WPHOST}.${DNSDOMAINNAME}
fi
kubectl -n blog1 wait pod -l app=wordpress --for condition=Ready --timeout 180s
fi

sleep 30
kubectl images -n ${WPNAMESPACE}
echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "Confirm wordpress pod and mysql pod are running with kubectl get pod -A"
echo "Open http://${EXTERNALIP}/wp-admin/install.php"
if [ ! -z ${DNSDOMAINNAME} ]; then
echo "or"
echo "Open http://${WPHOST}.${DNSDOMAINNAME}/wp-admin/install.php"
fi
echo ""
echo ""
echo ""
