#!/usr/bin/env bash
echo -e "\e[32mStarting $0 ....\e[m"
#########################################################
# Edit this section

# Sample "192.168.133.51-192.168.133.62"
IPRANGE="fixme"

#### Option ####
# If you want to change DNS domain name, you can chage it.
DNSDOMAINNAME="k8slab.internal"

DNSSVR=1
CERTMANAGER=0
REGISTRYFE=1
DASHBOARD=0
KEYCLOAK=0
GRAFANAMON=1
KUBEVIRT=1

# IF you have internal DNS, please comment out and set your own DNS server
#FORWARDDNS=192.168.8.1

#FORCE_LOCALIP=192.168.16.2
#########################################################
### UID Check ###
if [ ${EUID:-${UID}} != 0 ]; then
	echo "This script must be run as root"
	exit 1
else
	echo "I am root user."
fi

# HOSTNAME check
ping -c 3 $(hostname)
retvalping=$?
if [ ${retvalping} -ne 0 ]; then
	echo -e "\e[31m HOSTNAME was not configured correctly. \e[m"
	exit 255
fi

### Distribution Check ###
UBUNTUVER=$(lsb_release -rs)
case ${UBUNTUVER} in
"20.04")
	echo -e "\e[32m${UBUNTUVER} is OK. \e[m"
	;;
"22.04")
	echo "${UBUNTUVER} is OK.."
	#exit 255
	;;
*)
	echo -e "\e[31m${UBUNTUVER} is NG. \e[m"
	exit 255
	;;
esac

### ARCH ###
ARCH=$(dpkg --print-architecture)

BASEPWD=$(pwd)
source /etc/profile

### Cluster check ####
kubectl get pod
retavalcluser=$?
if [ ${retavalcluser} -ne 0 ]; then
	echo -e "\e[31m Kubernetes cluster is not found. \e[m"
	exit 255
fi
export KUBECONFIG=$HOME/.kube/config

#### LOCALIP (from kubectl) #########
if [ -z ${FORCE_LOCALIP} ]; then
	LOCALIPADDR=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
else
	LOCALIPADDR=${FORCE_LOCALIP}
fi
if [ -z ${LOCALIPADDR} ]; then
	echo -e "\e[31m Local IP address setting was failed, please set FORCE_LOCALIP and re-run.  \e[m"
	exit 255
else
	echo ${LOCALIPADDR}
fi

# SUDO Login
if [[ -z "${SUDO_USER}" ]]; then
	echo "You are root login."
else
	echo "You are sudo login."
fi
echo $SUDO_USER

## netplan configuration path
ls /etc/netplan/*.yaml
retvalnetplan=$?
if [ ${retvalnetplan} -eq 0 ]; then
	NETPLANPATH=$(ls /etc/netplan/*.yaml)
else
	echo "netplan was not configured. exit..."
	exit 255
fi
echo "netplan configuration file"
echo ${NETPLANPATH}

DNSHOSTIP=${LOCALIPADDR}
DNSHOSTNAME=$(hostname)

### Install command check ####
if type "kubectl" >/dev/null 2>&1; then
	echo "kubectl was already installed"
else
	echo "kubectl was not found. Please install kubectl and re-run"
	exit 255
fi

if type "helm" >/dev/null 2>&1; then
	echo "helm was already installed"
else
	if [ ! -f /usr/local/bin/helm ]; then
		curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /etc/apt/keyrings/helm.gpg >/dev/null
		apt install apt-transport-https --yes
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
		apt update
		apt -y install helm
		helm version
		helm completion bash >/etc/bash_completion.d/helm
		source /etc/bash_completion.d/helm
		helm repo add bitnami https://charts.bitnami.com/bitnami
		helm repo update
	fi
fi

# forget trap!
if [ ${IPRANGE} = "fixme" ]; then
	echo -e "\e[31m Please input your IPRANGE in this script!  \e[m"
	exit 255
fi
echo "Load balanacer IP range is ${IPRANGE}"

# fix inotify_init
sysctl fs.inotify.max_user_instances=512
sysctl fs.inotify.max_user_watches=65536
touch /etc/sysctl.d/10-k8s.conf
echo fs.inotify.max_user_instances=512 | tee -a /etc/sysctl.d/10-k8s.conf
echo fs.inotify.max_user_watches=65536 | tee -a /etc/sysctl.d/10-k8s.conf
sysctl -p
sysctl -a | grep fs.inotify.max

# Configure Metallb and ingress
# Installing Calico
TIGERAVER=3.26.1
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${TIGERAVER}/manifests/tigera-operator.yaml
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://raw.githubusercontent.com/projectcalico/calico/v${TIGERAVER}/manifests/custom-resources.yaml
sed -i -e "s@192.168.0.0@10.244.0.0@g" custom-resources.yaml
kubectl create -f custom-resources.yaml
kubectl get deployment -n calico-system calico-kube-controllers
sleep 15
kubectl -n tigera-operator wait pod -l k8s-app=tigera-operator --for condition=Ready
while [ "$(kubectl get deployment -n calico-system calico-kube-controllers --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
	echo "Deploying Calico controller Please wait...."
	kubectl get deployment -n calico-system calico-kube-controllers
	sleep 10
done
kubectl -n calico-system wait pod -l k8s-app=calico-kube-controllers --for condition=Ready
kubectl get deployment -n calico-system calico-kube-controllers

# Installing Metallb
echo "configure ${IPRANGE}"
METALLBVER=0.13.12
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v${METALLBVER}/config/manifests/metallb-native.yaml
sleep 2
kubectl get deployment -n metallb-system controller
while [ "$(kubectl get deployment -n metallb-system controller --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
	echo "Deploying metallb controller Please wait...."
	kubectl get deployment -n metallb-system controller
	sleep 30
done
cat <<EOF | kubectl create -n metallb-system -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - ${IPRANGE}
EOF
cat <<EOF | kubectl create -n metallb-system -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
spec:
  ipAddressPools:
  - first-pool
EOF
kubectl get deployment -n metallb-system controller

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx --create-namespace --namespace ingress-system
sleep 2
kubectl get deployment -n ingress-system ingress-nginx-controller
while [ "$(kubectl get deployment -n ingress-system ingress-nginx-controller --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
	echo "Deploying Ingress-nginx controller Please wait...."
	kubectl get deployment -n ingress-system ingress-nginx-controller
	sleep 30
done
kubectl get deployment -n ingress-system ingress-nginx-controller

INGRESS_IP=$(kubectl -n ingress-system get svc ingress-nginx-controller -ojsonpath='{.status.loadBalancer.ingress[0].ip}')

# Configutr local DNS Server
if [ ${DNSSVR} -eq 1 ]; then
	apt -y install bind9 bind9utils
	echo 'include "/etc/bind/named.conf.internal-zones";' >>/etc/bind/named.conf
	mv /etc/bind/named.conf.options /etc/bind/named.conf.options.orig
	cat <<EOF >/etc/bind/named.conf.options
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
	if [ ! -z ${FORWARDDNS} ]; then
		sed -i -e "s@// forwarders {@forwarders {@g" /etc/bind/named.conf.options
		sed -i -e "s@//      0.0.0.0;@     ${FORWARDDNS} ;@g" /etc/bind/named.conf.options
		sed -i -e "s@// };@};@g" /etc/bind/named.conf.options
	fi
	tsig-keygen -a hmac-sha256 externaldns-key >/etc/bind/external.key
	cat /etc/bind/external.key >>/etc/bind/named.conf.options
	chown root:bind /etc/bind/named.conf.options
	cat <<EOF >/etc/bind/named.conf.internal-zones
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
	cat <<'EOF' >/var/cache/bind/${DNSDOMAINNAME}.lan
$TTL 86400
EOF
	cat <<EOF >>/var/cache/bind/${DNSDOMAINNAME}.lan
@   IN  SOA     ${DNSHOSTNAME}.${DNSDOMAINNAME}. root.${DNSDOMAINNAME}. (
        2020050301  ;Serial
        3600        ;Refresh
        1800        ;Retry
        604800      ;Expire
        86400       ;Minimum TTL
)
        IN  NS      ${DNSDOMAINNAME}.
        IN  A       ${DNSHOSTIP}
        IN MX 10    ${DNSHOSTNAME}.${DNSDOMAINNAME}.
${DNSHOSTNAME}     IN  A       ${DNSHOSTIP}
xip		IN NS		ns-aws.sslip.io.
xip		IN NS		ns-gce.sslip.io.
xip		IN NS		ns-azure.sslip.io.
EOF
	if [ ! -z ${INGRESS_IP} ]; then
		cat <<EOF >>/var/cache/bind/${DNSDOMAINNAME}.lan
*.apps IN A ${INGRESS_IP}
EOF
	fi
	chown bind:bind /var/cache/bind/${DNSDOMAINNAME}.lan
	chmod g+w /var/cache/bind/${DNSDOMAINNAME}.lan
	systemctl restart named
	systemctl status named -l --no-pager
	#ETHDEV=$(grep ens ${NETPLANPATH} | tr -d ' ' | cut -d ":" -f1)
	ETHDEV=$(netplan get | sed 's/^[[:space:]]*//' | grep -A 1 "ethernet" | grep -v ethernet | cut -d ":" -f 1)
	netplan set network.ethernets.${ETHDEV}.nameservers.addresses="null"
	netplan set network.ethernets.${ETHDEV}.nameservers.search="null"
	netplan set network.ethernets.${ETHDEV}.nameservers.addresses=[${DNSHOSTIP}]
	netplan set network.ethernets.${ETHDEV}.nameservers.search=[${DNSDOMAINNAME}]
	netplan apply
	sleep 5
	cat <<EOF >/tmp/nsupdate.txt
server ${DNSHOSTIP}

update delete mail.${DNSDOMAINNAME}
update add mail.${DNSDOMAINNAME} 3600 IN A ${DNSHOSTIP}

EOF
	nsupdate -k /etc/bind/external.key /tmp/nsupdate.txt
	rm -rf /tmp/nsupdate.txt
	sleep 5
	echo ""
	echo "Sanity Test"
	echo ""
	host ${DNSHOSTNAME}.${DNSDOMAINNAME}. ${DNSHOSTIP}
	echo ""
	host mail.${DNSDOMAINNAME}. ${DNSHOSTIP}
	echo ""
	host abcd.apps.${DNSDOMAINNAME}. ${DNSHOSTIP}
	echo ""
	host www.yahoo.co.jp. ${DNSHOSTIP}
	echo ""
fi

# minio cert update
cat <<EOF >/tmp/nsupdate.txt
server ${DNSHOSTIP}

update delete minio.${DNSDOMAINNAME}
update add minio.${DNSDOMAINNAME} 3600 IN A ${DNSHOSTIP}

EOF
nsupdate -k /etc/bind/external.key /tmp/nsupdate.txt
rm -rf /tmp/nsupdate.txt
if [ -f /root/.minio/certs/private.key ]; then
	cd /root/.minio/certs/
	rm -rf cert.csr
	rm -rf extfile.conf
	rm -rf private.key
	rm -rf public.crt
	rm -rf rootCA*
	rm -rf CAs/rootCA.pem
	openssl genrsa -out rootCA.key 4096
	openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1825 -out rootCA.pem -subj "/C=JP/ST=Tokyo/L=Shibuya/O=cloudshift.corp/OU=development/CN=exmaple CA"
	openssl genrsa -out private.key 2048
	openssl req -subj "/CN=${LOCALIPADDR}" -sha256 -new -key private.key -out cert.csr
	cat <<EOF >extfile.conf
subjectAltName = DNS:minio.${DNSDOMAINNAME}, IP:${LOCALIPADDR}
EOF
	openssl x509 -req -days 365 -sha256 -in cert.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out public.crt -extfile extfile.conf
	chmod 600 ./private.key
	chmod 600 ./public.crt
	chmod 600 ./rootCA.pem
	mkdir -p /root/.minio/certs/CAs
	cp ./rootCA.pem /root/.minio/certs/CAs
	openssl x509 -in public.crt -text -noout | grep IP
	cp public.crt ~/.mc/certs/CAs/
	if [ -z $SUDO_USER ]; then
		echo "there is no sudo login"
	else
		mkdir -p /home/$SUDO_USER/.mc/certs/CAs/
		cp public.crt /home/$SUDO_USER/.mc/certs/CAs/
		chown -R $SUDO_USER /home/$SUDO_USER/.mc/
	fi
	cp /root/.minio/certs/public.crt /usr/share/ca-certificates/minio-dns.crt
	echo "minio-dns.crt" >>/etc/ca-certificates.conf
	update-ca-certificates
	systemctl restart minio.service
fi

# Install external-dns
TSIG_SECRET=$(grep secret /etc/bind/external.key | cut -d '"' -f 2)
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
        image: registry.k8s.io/external-dns/external-dns:v0.13.6
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
sleep 2
kubectl get deployment -n external-dns external-dns
while [ "$(kubectl get deployment -n external-dns external-dns --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
	echo "Deploying external-dns Please wait...."
	kubectl get deployment -n external-dns external-dns
	sleep 30
done
kubectl get deployment -n external-dns external-dns
DNSDOMAINNAME=$(kubectl -n external-dns get deployments.apps --output="jsonpath={.items[*].spec.template.spec.containers }" | jq | grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1)

# Install CertManager
if [ ${CERTMANAGER} -eq 1 ]; then
	git clone https://github.com/jetstack/cert-manager.git -b v1.4.0 --depth 1
	cd cert-manager/deploy/charts/cert-manager/
	cp -p Chart{.template,}.yaml
	sed -i -e "s/appVersion: v0.1.0/appVersion: v1.4.0/g" Chart.yaml
	kubectl create ns cert-manager
	kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.4.0/cert-manager.crds.yaml
	helm install cert-manager . -n cert-manager
	sleep 2
	kubectl get deployment -n cert-manager cert-manager
	while [ "$(kubectl get deployment -n cert-manager cert-manager --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
		echo "Deploying cert-manager Please wait...."
		kubectl get deployment -n cert-manager cert-manager
		sleep 30
	done
	kubectl get deployment -n cert-manager cert-manager
	cd ../../../../
	rm -rf cert-manager
	kubectl create ns sandbox
	cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: selfsigned-ca
  namespace: sandbox
spec:
  isCA: true
  commonName: selfsigned-ca
  duration: 438000h
  secretName: selfsigned-ca-cert
  privateKey:
    algorithm: RSA
    size: 2048
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ca-issuer
  namespace: sandbox
spec:
  ca:
    secretName: selfsigned-ca-cert
EOF
fi

# Install metric server
curl --retry 10 --retry-delay 3 --retry-connrefused -sSOL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
cat <<EOF | sed -i -e "/        imagePullPolicy: IfNotPresent$/r /dev/stdin" components.yaml
        command:
        - /metrics-server
        -  --kubelet-insecure-tls
        -  --kubelet-preferred-address-types=InternalIP
EOF
kubectl apply -f components.yaml
rm -rf components.yaml
sleep 2
kubectl -n kube-system get deployments.apps metrics-server
while [ "$(kubectl -n kube-system get deployments.apps metrics-server --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
	echo "Deploying Kubernetes metrics-server  Please wait...."
	kubectl -n kube-system get deployments.apps metrics-server
	sleep 30
done
kubectl -n kube-system get deployments.apps metrics-server

# Configure Kubernetes Dashboard
if [ ${DASHBOARD} -eq 1 ]; then

	DASHBOARDHOST=dashboard-$(hostname).${DNSDOMAINNAME}

	helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
	helm repo update

	helm show values kubernetes-dashboard/kubernetes-dashboard >values.yaml
	sed -i -e "s/- localhost/- ${DASHBOARDHOST}/g" values.yaml

	helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard --set=cert-manager.enabled=true --set=metrics-server.enabled=false --set=nginx.enabled=false -f values.yaml
	rm values.yaml

	kubectl -n kubernetes-dashboard wait pod -l app\.kubernetes\.io\/instance\=kubernetes\-dashboard --for condition=Ready

	cat <<EOF | kubectl -n kubernetes-dashboard apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
EOF
	cat <<EOF | kubectl -n kubernetes-dashboard apply -f -
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
	cat <<EOF | kubectl -n kubernetes-dashboard apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: "admin-user"   
type: kubernetes.io/service-account-token
EOF
	kubectl -n kubernetes-dashboard get ingress
	kubectl get secret admin-user -n kubernetes-dashboard -o jsonpath="{".data.token"}" | base64 -d
	echo "" >dashboard.token
	if [ -z $SUDO_USER ]; then
		echo "there is no sudo login"
	else
		cp dashboard.token /home/${SUDO_USER}/k8s-study-vanilla
		chown ${SUDO_USER} /home/${SUDO_USER}/k8s-study-vanilla/dashboard.token
	fi
fi

# Install Reigstory Frontend
if [ ${REGISTRYFE} -eq 1 ]; then
	if [ ${ARCH} = amd64 ]; then
		kubectl create namespace registry
		cat <<EOF | kubectl apply -n registry -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: pregistry-configmap
  namespace: registry
data:
  pregistry_host: ${LOCALIPADDR}
  pregistry_port: "5000"
---
kind: Service
apiVersion: v1
metadata:
  name: pregistry-frontend-clusterip
  namespace: registry
spec:
  selector:
    app: pregistry-frontend
  type: LoadBalancer
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    name: registry-http-frontend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pregistry-frontend-deployment
  namespace: registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pregistry-frontend
  template:
    metadata:
      labels:
        app: pregistry-frontend
    spec:
      containers:
      - name: pregistry-frontend-container
        image: konradkleine/docker-registry-frontend:v2
        ports:
        - containerPort: 80
        env:
        - name: ENV_DOCKER_REGISTRY_HOST
          valueFrom:
              configMapKeyRef:
                name: pregistry-configmap
                key: pregistry_host
        - name: ENV_DOCKER_REGISTRY_PORT
          valueFrom:
              configMapKeyRef:
                name: pregistry-configmap
                key: pregistry_port
EOF
		sleep 2
		kubectl -n registry get deployments.apps pregistry-frontend-deployment
		while [ "$(kubectl -n registry get deployments.apps pregistry-frontend-deployment --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
			echo "Deploying registry frontend  Please wait...."
			kubectl -n registry get deployments.apps pregistry-frontend-deployment
			sleep 30
		done
		kubectl -n registry get deployments.apps pregistry-frontend-deployment
		REGISTRY_EXTERNALIP=$(kubectl -n registry get service pregistry-frontend-clusterip | awk '{print $4}' | tail -n 1)
		kubectl -n registry annotate service pregistry-frontend-clusterip \
			external-dns.alpha.kubernetes.io/hostname=registryfe.${DNSDOMAINNAME}
		sleep 10
		host registryfe.${DNSDOMAINNAME}. ${DNSHOSTIP}
	fi
fi

# Keycloadk
if [ ${KEYCLOAK} -eq 1 ]; then
	debconf-set-selections <<<"postfix postfix/mailname string ${DNSHOSTNAME}.${DNSDOMAINNAME}"
	debconf-set-selections <<<"postfix postfix/main_mailer_type string 'Local only'"
	apt -y install postfix mailutils
	kubectl create ns keycloak
	kubectl -n keycloak create -f https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/latest/kubernetes-examples/keycloak.yaml
	kubectl -n keycloak get deployments.apps keycloak
	while [ "$(kubectl -n keycloak get deployments.apps keycloak --output="jsonpath={.status.conditions[*].status}" | cut -d' ' -f1)" != "True" ]; do
		echo "Deploying Keycloak  Please wait...."
		kubectl -n keycloak get deployments.apps keycloak
		sleep 30
	done
	kubectl -n keycloak get deployments.apps keycloak
	KEYCLOAK_EXTERNALIP=$(kubectl -n keycloak get service keycloak | awk '{print $4}' | tail -n 1)
	kubectl -n keycloak annotate service keycloak \
		external-dns.alpha.kubernetes.io/hostname=keycloak.${DNSDOMAINNAME}
	sleep 10
	host keycloak.${DNSDOMAINNAME}. ${DNSHOSTIP}
fi

# Grafana
if [ ${GRAFANAMON} -eq 1 ]; then
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm install prometheus prometheus-community/kube-prometheus-stack --create-namespace --namespace monitoring
	kubectl -n monitoring wait pod -l "app=kube-prometheus-stack-operator" --for condition=Ready
	kubectl -n monitoring get svc
	kubectl -n monitoring patch svc prometheus-kube-prometheus-prometheus -p '{"spec":{"type": "LoadBalancer"}}'
	kubectl -n monitoring patch svc prometheus-kube-state-metrics -p '{"spec":{"type": "LoadBalancer"}}'
	kubectl -n monitoring patch svc prometheus-grafana -p '{"spec":{"type": "LoadBalancer"}}'
	PROMETHEUSHOST=prometheus.${DNSDOMAINNAME}
	kubectl -n monitoring annotate service prometheus-kube-prometheus-prometheus \
		external-dns.alpha.kubernetes.io/hostname=${PROMETHEUSHOST}
	METRICHOST=metrics.${DNSDOMAINNAME}
	kubectl -n monitoring annotate service prometheus-kube-state-metrics \
		external-dns.alpha.kubernetes.io/hostname=${METRICHOST}
	GRAFANAHOST=grafana.${DNSDOMAINNAME}
	kubectl -n monitoring annotate service prometheus-grafana \
		external-dns.alpha.kubernetes.io/hostname=${GRAFANAHOST}
fi
# Kubevirt
if [ ${ARCH} = amd64 ]; then
	if [ $KUBEVIRT -eq 1 ]; then
		apt -y install cpu-checker
		kvm-ok
		retvalkvm=$?
		if [ ${retvalkvm} -eq 0 ]; then
			apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
			apt clean
			apt -y autoremove
			sed -i -e "s@pygrub PUx,@pygrub PUx,\n  /usr/libexec/qemu-kvm PUx, @" /etc/apparmor.d/usr.sbin.libvirtd
			systemctl reload apparmor.service
			#export VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases | grep tag_name | grep -v -- '-rc' | sort -r | head -1 | awk -F': ' '{print $2}' | sed 's/,//' | xargs)
			VERSION=v1.1.0
			echo $VERSION
			kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml
			kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml
			sleep 180
			kubectl -n kubevirt wait kv kubevirt --for condition=Available
			# Verify
			kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}"
			kubectl -n kubevirt get pod,daemonsets,deployments.apps
			# Install client
			VERSION=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.observedKubeVirtVersion}")
			ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/') || windows-amd64.exe
			echo ${ARCH}
			curl -L -o virtctl https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${ARCH}
			chmod +x virtctl
			install virtctl /usr/local/bin
			rm virtctl
			virtctl completion bash >/etc/bash_completion.d/virtctl
			source /etc/bash_completion.d/virtctl
			# CDI
			#export VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
			VERSION=v1.58.0
			kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
			kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml
			kubectl -n cdi wait pod -l app\.kubernetes\.io\/component=storage --for condition=Ready
			kubectl -n cdi get pod
			# VirtVNC
			wget -O virtvnc.yaml https://github.com/wavezhang/virtVNC/raw/master/k8s/virtvnc.yaml
			sed -i -e "s/NodePort/LoadBalancer/g" virtvnc.yaml
			kubectl create -f virtvnc.yaml
			rm virtvnc.yaml
		else
			echo "Virtualization is not supported in this node."
		fi
	fi
fi

rndc freeze ${DNSDOMAINNAME}
rndc thaw ${DNSDOMAINNAME}
rndc sync -clean ${DNSDOMAINNAME}

apt -y autoremove
apt clean
apt update
echo "*************************************************************************************"
echo "Here is cluster context."
echo -e "\e[1mkubectl config get-contexts \e[m"
kubectl config get-contexts
echo ""
echo -e "\e[1mDNS Server \e[m"
echo -n "DNS Domain Name is "
echo -e "\e[32m${DNSDOMAINNAME} \e[m"
echo -n "DNS DNS IP address is "
echo -e "\e[32m${DNSHOSTIP} \e[m"
echo " If you change dns server setting in client pc, you can access this server with this FQDN."
echo ""
echo -e "\e[1mKubernetes dashboard \e[m"
echo -e "\e[32m https://dashboard.${DASHBOARDHOST}/#/login \e[m"
echo ""
echo -e "\e[32m login token is cat ./dashboard.token  \e[m"
cat ./dashboard.token
echo ""
echo -e "\e[1mRegistry \e[m"
echo -e "\e[32m http://${LOCALIPADDR}:5000  \e[m"
echo "You need to set insecure-registry in your client side docker setting."
echo -e "\e[1mRegistry frontend UI \e[m"
echo -e "\e[32m http://${REGISTRY_EXTERNALIP}  \e[m"
echo "or"
echo -e "\e[32m http://registryfe.${DNSDOMAINNAME} \e[m"
echo ""
echo "Keycloak"
echo -e "\e[32m http://keycloak.${DNSDOMAINNAME}:8080 \e[m"
echo "or"
echo -e "\e[32m http://${KEYCLOAK_EXTERNALIP}:8080 \e[m"
echo -e "\e[32m username: admin / password: admin \e[m"
echo "and postfix was configured."
echo ""
echo " Copy HOME/.kube/config to your Windows/Mac/Linux desktop."
echo " You can access Kubernetes from your desktop!"
echo ""
echo "CNI/Loadbaancer/external-dns/Kubernetes dashboard/Registry Frontend were installed."
echo "Please check kubectl get pod -A All pod need to be running/completed."
echo "*************************************************************************************"
echo "Next Step"
echo ""
echo "Following is current DNS Server."
if type "systemd-resolve" >/dev/null 2>&1; then
	systemd-resolve --status | grep "Current DNS"
else
	resolvectl status | grep "Current DNS"
fi
echo "if ${LOCALIPADDR} is not set as local DNS resolver, please set DNS server to ${LOCALIPADDR}."
echo "You may be able to modify yaml file in /etc/netplan/, then execute netplan apply."
echo ""
echo ""
echo -e "\e[32m Run source /etc/profile \e[m"
echo "then,"
echo -e "\e[32m Run ./4-csi-storage.sh \e[m"
echo ""

cd ${BASEPWD}
chmod -x ./K1-kasten.sh
chmod +x ./result.sh
if [ -z $SUDO_USER ]; then
	echo "there is no sudo login"
else
	mkdir -p /home/${SUDO_USER}/k8s-study-vanilla/
	chown ${SUDO_USER}:${SUDO_USER} /home/${SUDO_USER}/k8s-study-vanilla/
	cp ./K1-kasten.sh /home/${SUDO_USER}/k8s-study-vanilla/
	cp ./P-wordpress.sh /home/${SUDO_USER}/k8s-study-vanilla/
	cp ./result.sh /home/${SUDO_USER}/k8s-study-vanilla/
	chown ${SUDO_USER}:${SUDO_USER} /home/${SUDO_USER}/k8s-study-vanilla/K1-kasten.sh
	chown ${SUDO_USER}:${SUDO_USER} /home/${SUDO_USER}/k8s-study-vanilla/P-wordpress.sh
	chown ${SUDO_USER}:${SUDO_USER} /home/${SUDO_USER}/k8s-study-vanilla/result.sh
	chmod +x /home/${SUDO_USER}/k8s-study-vanilla/result.sh
fi
chmod -x $0
ls
