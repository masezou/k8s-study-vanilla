#!/usr/bin/env bash

if [ ! -f ./vsphere-env ]; then
echo "There is no ./vsphere-env in same directory!!! Exit..."
exit 255
fi
source ./vsphere-env 

echo "Here is vSphere information"
echo $VSPHEREUSERNAME
echo $VSPHEREPASSWORD
echo $VSPHERESERVER

# Forget trap!
if [ ${VSPHERESERVER} = "YOUR_VCENTER_FQDN" ]; then
echo -e "\e[31m You haven't set environment value.  \e[m"
echo -e "\e[31m please set vCenter setting.  \e[m"
exit 255
fi

kubectl get sc | grep csi.vsphere
retval1=$?
if [ ${retval1} -ne 0 ]; then
chmod -x K3-kasten-vsphere.sh
echo "*************************************************************************************"
echo "vSphere CSI Driver was not found. No problem."
exit
fi

VSPHEREUSERNAMEBASE64=`echo -n "${VSPHEREUSERNAME}" | base64`
VSPHEREPASSWORDBASE64=`echo -n "${VSPHEREPASSWORD}" | base64`

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
    credential:
      secretType: VSphereKey
      secret:
        apiVersion: v1
        kind: Secret
        name: k10-vsphere-infra-secret
        namespace: kasten-io
EOF
rm -rf ./vsphere-env
echo "*************************************************************************************"
echo "Kasten Infrastructure was configured"

chmod -x K3-kasten-vsphere.sh

