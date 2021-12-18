#!/usr/bin/env bash

#########################################################
# Edit this section

# Sample "192.168.133.208/28" or "192.168.133.51-192.168.133.62"
IPRANGE="fixme"

#### Option ####
# For Wildcard entry - *.apps.domainame. Basically you can set  1st IP in IPRANGE
# Ex. IPRANGE is "192.168.133.208/28", 1st entry is 192.168.133.208.
HOSTSWILDCARDIP="192.168.133.208"

# If you want to change DNS domain name, you can chage it.
DNSDOMAINNAME="k8slab.internal"

#For vSphere CSI/Tanzu
VSPHEREUSERNAME="administrator@vsphere.local"
VSPHEREPASSWORD="YOUR_VCENTER_PASSWORD"
VSPHERESERVER="YOUR_VCENTER_FQDN"
VSPHERESERVERIP="YOUR_VCENTER_IP"
VSPPHEREDATASTORE="YOUR_DATASTORE"

# For VBR Repository setting.
VBRADDRESS="VBR_ADDRESS"
VBRUSERNAME="DOMAIN\administrator"
VBRPASSWORD="VBR_PASSWORD"
VBRREPONAME="DEFAULT Backup Repository 1"

#########################################################
sed -i -e "s/\=\"fixme\"/\=\"${IPRANGE}\"/g" 3-configk8s.sh
sed -i -e "s/192.168.133.208/${HOSTSWILDCARDIP}/g" 3-configk8s.sh
sed -i -e "s/k8slab.internal/${DNSDOMAINNAME}/g" 3-configk8s.sh

sed -i -e "s/administrator@vsphere.local/${VSPHEREUSERNAME}/g" 5-csi-vsphere.sh
sed -i -e "s/YOUR_VCENTER_PASSWORD/${VSPHEREPASSWORD}/g"  5-csi-vsphere.sh
sed -i -e "s/YOUR_VCENTER_FQDN/${VSPHERESERVER}/g" 5-csi-vsphere.sh
sed -i -e "s/YOUR_VCENTER_IP/${VSPHERESERVERIP}/g" 5-csi-vsphere.sh
sed -i -e "s/YOUR_DATASTORE/${VSPPHEREDATASTORE}/g" 5-csi-vsphere.sh

sed -i -e "s/VBR_ADDRESS/${VBRADDRESS}/g" K2-kasten-storage.sh
sed -i -e "s/DOMAIN\\administrator/${VBRUSERNAME}/g" K2-kasten-storage.sh
sed -i -e "s/VBR_PASSWORD/${VBRPASSWORD}/g" K2-kasten-storage.sh
sed -i -e "s/DEFAULT Backup Repository 1/${VBRREPONAME}/g" K2-kasten-storage.sh

./0-minio.sh
./1-tools.sh
./2-buildk8s-lnx.sh
./3-configk8s.sh
./4-csi-storage.sh
