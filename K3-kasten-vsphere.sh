#!/usr/bin/env bash
#########################################################

###VSPHERESETTING####
#VSPHEREUSERNAME="administrator@vsphere.local"
#VSPHEREPASSWORD="YOUR_VCENTER_PASSWORD"
#VSPHERESERVER="YOUR_VCENTER_FQDN"

#########################################################

echo "Here is vSphere information"
echo $VSPHEREUSERNAME
echo $VSPHEREPASSWORD
echo $VSPHERESERVER

# Forget trap!
if [ -z ${VSPHERESERVER} ]; then
	echo "vSphere profile is not set"
	exit 0
fi

kubectl get sc | grep csi.vsphere
retval1=$?
if [ ${retval1} -ne 0 ]; then
	chmod -x K3-kasten-vsphere.sh
	echo "*************************************************************************************"
	echo "vSphere CSI Driver was not found. No problem."
	exit
fi

VSPHEREUSERNAMEBASE64=$(echo -n "${VSPHEREUSERNAME}" | base64)
VSPHEREPASSWORDBASE64=$(echo -n "${VSPHEREPASSWORD}" | base64)

cat <<EOF | kubectl apply -n kasten-io -f -
# Standard Kubernetes API Version declaration. Required.
apiVersion: v1
# Standard Kubernetes Kind declaration. Required.
kind: Secret
# Standard Kubernetes metadata. Required.
metadata:
  # Secret name. May be any valid Kubernetes secret name. Required.
  name: k10-vsphere-infra-secret
  # Secret namespace. Required. Must be namespace where K10 is installed
  namespace: kasten-io
# Standard Kubernetes secret type. Must be Opaque. Required.
type: Opaque
# Secret data payload. Required.
data:
  # Base64 encoded value for a vSphere user.
  vsphere_user: ${VSPHEREUSERNAMEBASE64}
  # Base64 encoded value for a vSphere password.
  vsphere_password: ${VSPHEREPASSWORDBASE64}
EOF

cat <<EOF | kubectl apply -n kasten-io -f -
apiVersion: config.kio.kasten.io/v1alpha1
kind: Profile
metadata:
  name: vsphere-profile
  namespace: kasten-io
spec:
  type: Infra
  infra:
    type: VSphere
    vsphere:
      serverAddress: ${VSPHERESERVER}
      taggingEnabled: true
      categoryName: k8sCategory
    credential:
      secretType: VSphereKey
      secret:
        apiVersion: v1
        kind: Secret
        name: k10-vsphere-infra-secret
        namespace: kasten-io
EOF

if [ -f /usr/local/bin/k10tools ]; then
cat << EOF > /etc/profile.d/k10tools-vsphere.sh
#This is for k10tools with vSphere snapshot
export VSPHERE_ENDPOINT=${VSPHERESERVER}
export VSPHERE_USERNAME=${VSPHEREUSERNAME}
export VSPHERE_PASSWORD=${VSPHEREPASSWORD}
#category name can be found from the vsphere infrastructure profile
EOF
cat << 'EOF' >> /etc/profile.d/k10tools-vsphere.sh
export VSPHERE_SNAPSHOT_TAGGING_CATEGORY=$(kubectl -n kasten-io get profiles $(kubectl -n kasten-io get profiles -o=jsonpath='{.items[?(@.spec.infra.type=="VSphere")].metadata.name}') -o jsonpath='{.spec.infra.vsphere.categoryName}')
EOF
fi

echo "*************************************************************************************"
echo "Kasten Infrastructure was configured"
kubectl -n kasten-io get profiles

chmod -x $0
