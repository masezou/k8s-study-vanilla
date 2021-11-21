#!/usr/bin/env bash

# Sample "192.168.133.208/28" or "192.168.133.51-192.168.133.62"
IPRANGE="fixme"

# If you want to change DNS domain name, you can chage it.
DNSDOMAINNAME="k8slab.internal"

#########################################################
### UID Check ###
if [ ${EUID:-${UID}} != 0 ]; then
    echo "This script must be run as root"
    exit 1
else
    echo "I am root user."
fi

### Distribution Check ###
lsb_release -d | grep Ubuntu | grep 20.04
DISTVER=$?
if [ ${DISTVER} = 1 ]; then
    echo "only supports Ubuntu 20.04 server"
    exit 1
else
    echo "Ubuntu 20.04=OK"
fi

#### LOCALIP #########
ip address show ens160 >/dev/null
retval=$?
if [ ${retval} -eq 0 ]; then
        LOCALIPADDR=`ip -f inet -o addr show ens160 |cut -d\  -f 7 | cut -d/ -f 1`
else
  ip address show ens192 >/dev/null
  retval2=$?
  if [ ${retval2} -eq 0 ]; then
        LOCALIPADDR=`ip -f inet -o addr show ens192 |cut -d\  -f 7 | cut -d/ -f 1`
  else
        LOCALIPADDR=`ip -f inet -o addr show eth0 |cut -d\  -f 7 | cut -d/ -f 1`
  fi
fi
echo ${LOCALIPADDR}

DNSHOSTIP=${LOCALIPADDR}
DNSHOSTNAME=`hostname`

### Install command check ####
if type "kubectl" > /dev/null 2>&1
then
    echo "kubectl was already installed"
else
    echo "kubectl was not found. Please install kubectl and re-run"
    exit 255
fi

# forget trap!
if [ ${IPRANGE} = "fixme" ]; then
echo -e "\e[31m Please input your IPRANGE in this script!  \e[m"
exit 255
fi
echo "Load balanacer IP range is ${IPRANGE}"

kubectl get pod 
retavalcluser=$?
if [ ${retavalcluser} -ne 0 ]; then
echo -e "\e[31m Kubernetes cluster is not found. \e[m"
exit 255
fi


export KUBECONFIG=$HOME/.kube/config

# Configure Metallb and ingress
echo "configure ${IPRANGE}"
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl diff -f - -n kube-system
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/main/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/main/manifests/metallb.yaml
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${IPRANGE}
EOF
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

while [ "$(kubectl get deployment -n ingress-nginx ingress-nginx-controller --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
	echo "Deploying Ingress-nginx controller Please wait...."
    kubectl get deployment -n ingress-nginx ingress-nginx-controller
	sleep 30
done

# Configutr local DNS Server
apt -y install bind9 bind9utils
echo 'include "/etc/bind/named.conf.internal-zones";' >> /etc/bind/named.conf
mv /etc/bind/named.conf.options /etc/bind/named.conf.options.orig
cat << EOF > /etc/bind/named.conf.options
acl internal-network {
        127.0.0.0/8;
        10.0.0.0/8;
        172.16.0.0/12;
        192.168.0.0/16;
};
options {
        directory "/var/cache/bind";

        // If there is a firewall between you and nameservers you want
        // to talk to, you may need to fix the firewall to allow multiple
        // ports to talk.  See http://www.kb.cert.org/vuls/id/800113

        // If your ISP provided one or more IP addresses for stable
        // nameservers, you probably want to use them as forwarders.
        // Uncomment the following block, and insert the addresses replacing
        // the all-0's placeholder.

        // forwarders {
        //      0.0.0.0;
        // };

        //========================================================================
        // If BIND logs error messages about the root key being expired,
        // you will need to update your keys.  See https://www.isc.org/bind-keys
        //========================================================================
        dnssec-validation auto;

        listen-on-v6 { none; };
        allow-query { localhost; internal-network; };
        recursion yes;
};
EOF
tsig-keygen -a hmac-sha256 externaldns-key > /etc/bind/external.key
cat /etc/bind/external.key>> /etc/bind/named.conf.options
chown root:bind /etc/bind/named.conf.options
cat << EOF > /etc/bind/named.conf.internal-zones
zone "${DNSDOMAINNAME}" IN {
        type master;
        file "/var/cache/bind/${DNSDOMAINNAME}.lan";
        allow-transfer {
          key "externaldns-key";
        };
        update-policy {
          grant externaldns-key zonesub ANY;
        };
};
zone "0.0.10.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.16.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.17.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.18.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.19.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.20.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.21.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.22.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.23.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.24.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.25.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.26.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.27.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.28.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.29.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.30.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.31.172.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
zone "0.168.192.in-addr.arpa" IN {
        type master;
        file "/etc/bind/db.empty";
        allow-update { none; };
};
EOF
sed -i -e 's/bind/bind -4/g' /etc/default/named
cat << 'EOF' >/var/cache/bind/${DNSDOMAINNAME}.lan
$TTL 86400
EOF
cat << EOF >>/var/cache/bind/${DNSDOMAINNAME}.lan
@   IN  SOA     ${DNSHOSTNAME}.${DNSDOMAINNAME}. root.${DNSDOMAINNAME}. (
        2020050301  ;Serial
        3600        ;Refresh
        1800        ;Retry
        604800      ;Expire
        86400       ;Minimum TTL
)
        IN  NS      ${DNSDOMAINNAME}.
        IN  A       ${DNSHOSTIP}
${DNSHOSTNAME}     IN  A       ${DNSHOSTIP}
minio IN A ${DNSHOSTIP}
EOF
chown bind:bind /var/cache/bind/${DNSDOMAINNAME}.lan
chmod g+w /var/cache/bind/${DNSDOMAINNAME}.lan
systemctl restart named
systemctl status named -l --no-pager 
sleep 5
echo ""
echo "Sanity Test"
echo ""
host ${DNSHOSTNAME}.${DNSDOMAINNAME}. ${DNSHOSTIP}
echo ""
host minio.${DNSDOMAINNAME}. ${DNSHOSTIP}
echo ""
host www.yahoo.co.jp. ${DNSHOSTIP}
echo ""

TSIG_SECRET=`grep secret /etc/bind/external.key | cut -d '"' -f 2`

# Install external-dns
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: external-dns
  labels:
    name: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
  namespace: external-dns
rules:
- apiGroups:
  - ""
  resources:
  - services
  - endpoints
  - pods
  - nodes
  verbs:
  - get
  - watch
  - list
- apiGroups:
  - extensions
  - networking.k8s.io
  resources:
  - ingresses
  verbs:
  - get
  - list
  - watch
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
  namespace: external-dns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: external-dns
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: external-dns
spec:
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: k8s.gcr.io/external-dns/external-dns:v0.10.1
        args:
        - --provider=rfc2136
        - --registry=txt
        - --txt-owner-id=k8s
        - --txt-prefix=external-dns-
        - --source=service
        - --source=ingress
        - --domain-filter=${DNSDOMAINNAME}
        - --rfc2136-host=${DNSHOSTIP}
        - --rfc2136-port=53
        - --rfc2136-zone=${DNSDOMAINNAME}
        - --rfc2136-tsig-secret=${TSIG_SECRET}
        - --rfc2136-tsig-secret-alg=hmac-sha256
        - --rfc2136-tsig-keyname=externaldns-key
        - --rfc2136-tsig-axfr
        #- --interval=10s
        #- --log-level=debug
EOF

# Configure Kubernetes Dashboard
kubectl create namespace kubernetes-dashboard
mkdir certs
cd certs
openssl genrsa -out dashboard.key 2048
cat <<EOF> openssl.conf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = VA
L = Somewhere
O = MyOrg
OU = MyOU
CN = MyServerName

[v3_req]
subjectAltName = @alt_names

[alt_names]
IP.1 = 127.0.0.1
DNS.1 = localhost
EOF
openssl req -new -x509 -nodes -days 365 -key dashboard.key -out dashboard.crt -config openssl.conf
openssl x509 -in dashboard.crt -text -noout| grep IP
kubectl create secret generic kubernetes-dashboard-certs --from-file=dashboard.key --from-file=dashboard.crt -n kubernetes-dashboard
cd ..

kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.4.0/aio/deploy/recommended.yaml
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: kubernetes-dashboard
  name: dashboard-service-lb
  namespace: kubernetes-dashboard
spec:
  type: LoadBalancer
  ports:
    - name: dashboard-service-lb
      protocol: TCP
      port: 443
      nodePort: 30085
      targetPort: 8443
  selector:
    k8s-app: kubernetes-dashboard
EOF
rm -rf certs

# Dashboard FQDN
kubectl -n kubernetes-dashboard annotate service dashboard-service-lb \
    external-dns.alpha.kubernetes.io/hostname=dashboard.${DNSDOMAINNAME}
sleep 10

host dashboard.${DNSDOMAINNAME}. ${DNSHOSTIP}

kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}" > dashboard.token
echo "" >> dashboard.token

# Installing metric server
curl -OL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
cat << EOF | sed -i -e "/        imagePullPolicy: IfNotPresent$/r /dev/stdin" components.yaml
        command:
        - /metrics-server
        -  --kubelet-insecure-tls
        -  --kubelet-preferred-address-types=InternalIP
EOF
kubectl apply -f components.yaml
rm -rf components.yaml

EXTERNALIP=`kubectl -n kubernetes-dashboard get service dashboard-service-lb| awk '{print $4}' | tail -n 1`

echo "*************************************************************************************"
echo "Here is cluster context"
echo "kubectl config get-contexts"
kubectl config get-contexts
echo ""
echo "CNI/Loadbaancer/external-dns and Dashboard was installed."
echo "Please check kubectl get pod -A"
echo ""
echo "DNS Server was configured."
echo "DNS Domain Name is ${DNSDOMAINNAME}"
echo "DNS DNS IP address is ${DNSHOSTIP}"
echo "If you want to use external-dns, please add annotation in Kind: Service which sets loadbalancer"
echo "    external-dns.alpha.kubernetes.io/hostname: YOUR_HOSTNAME.${DNSDOMAINNAME}"
echo " or "
echo " kubectl -n <Namespace> annotate service <service> \ "
echo "    external-dns.alpha.kubernetes.io/hostname=${DNSDOMAINNAME}"
echo ""
echo ""
echo "You can access Kubernetes dashboard"
echo -e "\e[32m https://${EXTERNALIP}/#/login  \e[m"
echo "or"
echo -e "\e[32m https://dashboard.${DNSDOMAINNAME}/#/login \e[m"
echo ""
echo -e "\e[32m login token is cat ./dashboard.token  \e[m"
cat ./dashboard.token
echo ""
echo "You can access minio dashboard"
echo -e "\e[32m https://${LOCALIPADDR}:9001  \e[m"
echo "or"
echo -e "\e[32m https://minio.${DNSDOMAINNAME}:9001 \e[m"
echo ""
echo -e "\e[32m login credential minioadminuser/minioadminuser  \e[m"
echo ""
echo "Registry server"
echo -e "\e[32m http://${LOCALIPADDR}:5000  \e[m"
echo ""
echo "*************************************************************************************"
echo "Next Step"
echo ""
echo -e "\e[32m Run source /etc/profile \e[m"
echo "then,"
echo -e "\e[32m Run ./4-csi-storage.sh \e[m"
echo ""

chmod -x ./3-configk8s.sh
