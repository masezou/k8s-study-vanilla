#!/usr/bin/env bash

#########################################################

#TENANTNAMESPACE=minio-tenant1
#DNSDOMAINNAME=k8slab.internal
#DNSHOST=12.168.133.2

#########################################################

if [ -z ${TENANTNAMESPACE} ]; then
TENANTNAMESPACE=`kubectl get tenant -A| grep Initialized| cut -d " " -f1`
fi
if [ -z ${DNSDOMAINNAME} ]; then
DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
fi
if [ -z ${DNSHOST} ]; then
DNSHOST=`kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'`
fi

# Register external DNS
kubectl -n ${TENANTNAMESPACE} annotate service minio external-dns.alpha.kubernetes.io/hostname=${TENANTNAMESPACE}api.${DNSDOMAINNAME}
kubectl -n ${TENANTNAMESPACE} annotate service ${TENANTNAMESPACE}-console external-dns.alpha.kubernetes.io/hostname=${TENANTNAMESPACE}-console.${DNSDOMAINNAME}
host ${TENANTNAMESPACE}api.${DNSDOMAINNAME} ${DNSHOST}
host ${TENANTNAMESPACE}-console.${DNSDOMAINNAME} ${DNSHOST}

# Create certificate for tenant
LOCALHOSTNAMEAPI=${TENANTNAMESPAC}api.${DNSDOMAINNAME}
LOCALIPADDRAPI=`kubectl -n ${TENANTNAMESPACE} get service minio | awk '{print $4}' | tail -n 1`
LOCALHOSTNAMECONSOLE=${TENANTNAMESPAC}-console.${DNSDOMAINNAME}
LOCALIPADDRCONSOLE=`kubectl -n ${TENANTNAMESPACE} get service ${TENANTNAMESPACE}-console | awk '{print $4}' | tail -n 1`
openssl genrsa -out rootCA.key 4096
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1825 -out rootCA.pem -subj "/C=JP/ST=Tokyo/L=Shibuya/O=cloudshift.corp/OU=development/CN=exmaple CA"
openssl genrsa -out private.key 2048
openssl req -subj "/CN=${LOCALIPADDRAPI}" -sha256 -new -key private.key -out cert.csr
cat << EOF > extfile.conf
subjectAltName = DNS:${LOCALHOSTNAMEAPI}, DNS:${LOCALHOSTNAMECONSOLE}, IP:${LOCALIPADDRAPI}, IP:${LOCALIPADDRCONSOLE}
EOF
openssl x509 -req -days 365 -sha256 -in cert.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out public.crt -extfile extfile.conf
chmod 600 ./private.key
chmod 600 ./public.crt
chmod 600 ./rootCA.pem

mkdir -p ~/.mc/certs/CAs/
cp public.crt ~/.mc/certs/CAs/
cp public.crt /usr/share/ca-certificates/${TENANTNAMESPAC}.crt
echo "${TENANTNAMESPAC}.crt">>/etc/ca-certificates.conf
update-ca-certificates

echo ""
echo "*************************************************************************************"
echo "Upload following certificate to Minio Tenant"
echo "private.key / public.crt / rootCA.pem"
echo ""

