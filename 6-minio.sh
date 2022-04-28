#!/usr/bin/env bash

#########################################################
# If you want to create Minio Tenant
TENANTCREATE=1
TENANTNAMESPACE=minio-tenant1
TENANTCAPCITY=200Gi
# SC = csi-hostpath-sc / local-hostpath / nfs-sc / nfs-csi / vsphere-sc / example-vanilla-rwo-filesystem-sc / cstor-csi-disk
TENANTSC=nfs-sc
#DNSDOMAINNAME=k8slab.internal
#DNSHOST=12.168.133.2
#MCLOGINUSER=miniologinuser
#MCLOGINPASSWORD=miniologinuser

#########################################################
### Cluster check ####
kubectl get pod
retavalcluser=$?
if [ ${retavalcluser} -ne 0 ]; then
echo -e "\e[31m Kubernetes cluster is not found. \e[m"
exit 255
fi

# Taint Check
kubectl describe node `hostname` | grep Taint | grep none
retvaltaint=$?
if [ ${retvaltaint} -ne 0 ]; then
echo -e "\e[31m It seemed taint was set. Exit. \e[m"
exit 255
fi

source /etc/profile.d/krew.sh
if [ -z ${DNSDOMAINNAME} ]; then
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
echo $DNSDOMAINNAME
fi
if [ -z ${DNSHOST} ]; then
DNSHOST=`kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'`
echo $DNSHOST
fi

# Checking Minio Operator
kubectl get ns minio-operator
retvalmco=$?
if [ ${retvalmco} -ne 0 ]; then
echo "Minio operator was not deployed. please deploy Minio Operator at first."
# Minio Operator
MINIO_OPERATOR=1
if [ ${MINIO_OPERATOR} -eq 1 ]; then
echo "Under deploying Minio Operator"
kubectl minio init
sleep 2
kubectl -n minio-operator wait pod -l operator=leader --for condition=Ready
kubectl -n minio-operator patch service console -p '{"spec":{"type": "LoadBalancer"}}'
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
kubectl -n minio-operator annotate service console external-dns.alpha.kubernetes.io/hostname=minio-console.${DNSDOMAINNAME}
kubectl -n minio-operator patch deployment minio-operator -p '{"spec":{"replicas": 1}}'
echo "done"
fi
fi
if [ ${TENANTCREATE} -eq 1 ]; then
echo "Deploying Minio Tenant $TENANTNAMESPACE"
kubectl create ns ${TENANTNAMESPACE} 
kubectl minio tenant create ${TENANTNAMESPACE} \
    --servers 1 \
    --volumes 4 \
    --capacity ${TENANTCAPCITY} \
    --namespace ${TENANTNAMESPACE} \
    --storage-class ${TENANTSC}
echo "Under deploying minio tenant ${TENANTNAMESPACE}"
sleep 2
kubectl -n ${TENANTCREATE} wait pod -l v1\.min\.io\/tenant=${TENANTCREATE} --for condition=Ready
#kubectl -n ${TENANTNAMESPACE} get pod ${TENANTNAMESPACE}-pool-0-0
#while [ "$(kubectl -n ${TENANTNAMESPACE} get pod ${TENANTNAMESPACE}-pool-0-0 --output="jsonpath={.status.phase}")" != "Running" ]; do
##    echo "Under deploying minio tenant ${TENANTNAMESPACE}"
#    kubectl -n ${TENANTNAMESPACE} get pod ${TENANTNAMESPACE}-pool-0-0
#    sleep 5
#done
#    kubectl -n ${TENANTNAMESPACE} get pod ${TENANTNAMESPACE}-pool-0-0

cat <<EOF | kubectl apply -n ${TENANTNAMESPACE} -f -
apiVersion: v1
kind: Service
metadata:
  namespace: ${TENANTNAMESPACE} 
  name: minio
  labels:
    component: ${TENANTNAMESPACE} 
spec:
  type: LoadBalancer
  ports:
    - name: https-minio
      port: 443
      targetPort: 9000
      protocol: TCP
  selector:
    v1.min.io/tenant: ${TENANTNAMESPACE} 
EOF
cat <<EOF | kubectl apply -n ${TENANTNAMESPACE} -f -
apiVersion: v1
kind: Service
metadata:
  namespace: ${TENANTNAMESPACE} 
  name:  ${TENANTNAMESPACE}-console
spec:
  type: LoadBalancer
  ports:
    - name: https-console
      port: 9443
      protocol: TCP
      targetPort: 9443
  selector:
    v1.min.io/console: ${TENANTNAMESPACE}-console
EOF
LOCALHOSTNAMEAPI=${TENANTNAMESPACE}-api.${DNSDOMAINNAME}
LOCALHOSTNAMECONSOLE=${TENANTNAMESPACE}-console.${DNSDOMAINNAME}
kubectl -n ${TENANTNAMESPACE} annotate service minio external-dns.alpha.kubernetes.io/hostname=${LOCALHOSTNAMEAPI}
kubectl -n ${TENANTNAMESPACE} annotate service ${TENANTNAMESPACE}-console external-dns.alpha.kubernetes.io/hostname=${LOCALHOSTNAMECONSOLE}
# Create certificate for tenant
LOCALIPADDRAPI=`kubectl -n ${TENANTNAMESPACE} get service minio | awk '{print $4}' | tail -n 1`
LOCALIPADDRCONSOLE=`kubectl -n ${TENANTNAMESPACE} get service ${TENANTNAMESPACE}-console | awk '{print $4}' | tail -n 1`
openssl genrsa -out rootCA.key 4096
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1825 -out rootCA.pem -subj "/C=JP/ST=Tokyo/L=Shibuya/O=cloudshift.corp/OU=development/CN=exmaple CA"
openssl genrsa -out private.key 2048
openssl req -subj "/CN=${LOCALIPADDRAPI}" -sha256 -new -key private.key -out cert.csr
cat << EOF > extfile.conf
subjectAltName = DNS.1:${LOCALHOSTNAMEAPI}, DNS.2:${LOCALHOSTNAMECONSOLE}, IP.1:${LOCALIPADDRAPI}, IP.2:${LOCALIPADDRCONSOLE}
EOF
openssl x509 -req -days 365 -sha256 -in cert.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out public.crt -extfile extfile.conf
mkdir -p ${TENANTNAMESPACE}-cert
cd ${TENANTNAMESPACE}-cert
mv ../private.key .
mv ../public.crt .
mv ../rootCA.pem .
chmod 600 ./private.key
chmod 600 ./public.crt
chmod 600 ./rootCA.pem
cd ..

if [ ${EUID:-${UID}} = 0 ]; then
cp ${TENANTNAMESPACE}-cert/public.crt /usr/share/ca-certificates/${TENANTNAMESPACE}.crt
echo "${TENANTNAMESPACE}.crt">>/etc/ca-certificates.conf
update-ca-certificates
fi

MCLOGINUSER=`kubectl -n ${TENANTNAMESPACE} get secret ${TENANTNAMESPACE}-user-1 -ojsonpath="{.data."CONSOLE_ACCESS_KEY"}{'\n'}" |base64 --decode`
MCLOGINPASSWORD=`kubectl -n ${TENANTNAMESPACE} get secret ${TENANTNAMESPACE}-user-1 -ojsonpath="{.data."CONSOLE_SECRET_KEY"}{'\n'}" |base64 --decode`
sleep 5
mkdir -p ~/.mc/certs/CAs/
cp ${TENANTNAMESPACE}-cert/public.crt ~/.mc/certs/CAs/
mc --insecure alias set ${TENANTNAMESPACE} https://${LOCALIPADDRAPI} ${MCLOGINUSER} ${MCLOGINPASSWORD} --api S3v4
if [ -z $SUDO_USER ]; then
   echo "there is no sudo login"
else
cp -rf ${TENANTNAMESPACE}-cert /home/${SUDO_USER}/
chown -R ${SUDO_USER}:${SUDO_USER} /home/${SUDO_USER}/${TENANTNAMESPACE}-cert
sudo -u $SUDO_USER mkdir -p /home/$SUDO_USER/.mc/certs/CAs/
sudo -u $SUDO_USER cp /home/${SUDO_USER}/${TENANTNAMESPACE}-cert/public.crt /home/$SUDO_USER/.mc/certs/CAs/
sudo -u $SUDO_USER mc --insecure alias set ${TENANTNAMESPACE} https://${LOCALIPADDRAPI} ${MCLOGINUSER} ${MCLOGINPASSWORD} --api S3v4
fi

mc --insecure admin info ${TENANTNAMESPACE}

fi

echo ""
echo "*************************************************************************************"
if [ ${MINIO_OPERATOR} -eq 1 ]; then
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
MINIOOP_EXTERNALIP=`kubectl -n minio-operator get service console | awk '{print $4}' | tail -n 1`
echo "Open following URL with Chrome browser"
echo "http://minio-console.${DNSDOMAINNAME}:9090/login"
echo "Or"
echo "http://${MINIOOP_EXTERNALIP}:9090/login"
echo ""
echo "Login with JWT"
echo "JWT"
sa_secret=$(kubectl get serviceaccount console-sa -o jsonpath="{.secrets[0].name}" --namespace minio-operator)
kubectl get secret $sa_secret --namespace minio-operator -ojsonpath="{.data.token}{'\n'}" | base64 --decode > minio-operator.token
echo "" >> minio-operator.token
cat minio-operator.token
echo ""
echo ""
fi
if [ ${TENANTCREATE} -eq 1 ]; then
echo "Upload following certificate to Minio Tenant in Minio Operator UI"
echo "private.key / public.crt / rootCA.pem"
echo ""
echo "API endpoint"
echo "https://${LOCALHOSTNAMEAPI}"
echo "or"
echo "https://${LOCALIPADDRAPI}"
echo "Console"
echo "https://${LOCALHOSTNAMECONSOLE}:9443"
echo "or"
echo "https://${LOCALIPADDRCONSOLE}:9443"
echo ""
echo "Credential"
echo "${MCLOGINUSER} / ${MCLOGINPASSWORD}"
fi
echo ""

chmod -x $0
ls
