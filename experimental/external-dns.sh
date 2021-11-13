#!/usr/bin/env bash
DNSHOSTIP=192.168.134.2
OS_API=192.168.134.49
OS_APPS=192.168.134.48
DNSHOSTNAME=ent17-dns
DNSDOMAINNAME=ent17.cloudshift.corp

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

# DNS Server
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
        file "/etc/bind/${DNSDOMAINNAME}.lan";
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
cat << 'EOF' >/etc/bind/${DNSDOMAINNAME}.lan
$TTL 86400
EOF
cat << EOF >>/etc/bind/${DNSDOMAINNAME}.lan
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
api       IN  A   ${OS_API}
*.apps  IN  A   ${OS_APPS}
EOF
systemctl restart named
systemctl status named -l --no-pager 
sleep 5
echo ""
echo "Sanity Test"
echo ""
host ${DNSHOSTNAME}.${DNSDOMAINNAME}. ${DNSHOSTIP}
echo ""
host api.${DNSDOMAINNAME}. ${DNSHOSTIP}
echo ""
host abcd.apps.${DNSDOMAINNAME}. ${DNSHOSTIP}
echo ""
host www.yahoo.co.jp. ${DNSHOSTIP}
echo ""

TSIG_SECRET=`grep secret /etc/bind/external.key | cut -d '"' -f 2`
echo ""
echo ""
echo "DNS Key is ${TSIG_SECRET}"
echo ""

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
        image: k8s.gcr.io/external-dns/external-dns:v0.7.6
        args:
        - --registry=txt
        - --txt-prefix=external-dns-
        - --txt-owner-id=k8s
        - --provider=rfc2136
        - --rfc2136-host=${DNSHOSTIP}
        - --rfc2136-port=53
        - --rfc2136-zone=${DNSDOMAINNAME}
        - --rfc2136-tsig-secret=${TSIG_SECRET}
        - --rfc2136-tsig-secret-alg=hmac-sha256
        - --rfc2136-tsig-keyname=externaldns-key
        - --rfc2136-tsig-axfr
        - --source=ingress
        - --domain-filter=${DNSDOMAINNAME}
EOF

echo "************************"
echo "external-dns was configured"

chmod -x ./external-dns.sh