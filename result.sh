#!/usr/bin/env bash

DNSDOMAINNAME="k8slab.internal"
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

DNSHOSTIP=${LOCALIPADDR}
DNSHOSTNAME=`hostname`
DASHBOARD_EXTERNALIP=`kubectl -n kubernetes-dashboard get service dashboard-service-lb| awk '{print $4}' | tail -n 1`
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}" > dashboard.token
echo "" >> dashboard.token
REGISTRY_EXTERNALIP=`kubectl -n registry get service pregistry-frontend-clusterip | awk '{print $4}' | tail -n 1`

echo "*************************************************************************************"
echo "Here is cluster context."
echo -e "\e[1mkubectl config get-contexts \e[m"
kubectl config get-contexts
echo ""
echo -e "\e[1mmetallb loadbalancer IP address range \e[m"
kubectl -n metallb-system get configmaps config -o jsonpath='{.data.config}'
echo ""
echo -e "\e[1mDNS Server \e[m"
echo -n "DNS Domain Name is "
echo -e "\e[32m${DNSDOMAINNAME} \e[m"
echo -n "DNS DNS IP address is "
echo -e "\e[32m${DNSHOSTIP} \e[m"
echo " If you change dns server setting in client pc, you can access this server with this FQDN."
echo ""
echo -e "\e[1mKubernetes dashboard \e[m"
echo -e "\e[32m https://${DASHBOARD_EXTERNALIP}/#/login  \e[m"
echo "or"
echo -e "\e[32m https://dashboard.${DNSDOMAINNAME}/#/login \e[m"
echo ""
echo -e "\e[32m login token is cat ./dashboard.token  \e[m"
cat ./dashboard.token
echo ""
echo -e "\e[1mMinio dashboard  \e[m"
echo -e "\e[32m https://${LOCALIPADDR}:9001  \e[m"
echo "or"
echo -e "\e[32m https://minio.${DNSDOMAINNAME}:9001 \e[m"
echo ""
echo -n " login credential is "
echo -e "\e[32mminioadminuser/minioadminuser  \e[m"
echo ""
echo -e "\e[1mRegistry \e[m"
echo -e "\e[32m http://${LOCALIPADDR}:5000  \e[m"
echo "You need to set insecure-registry in your client side docker setting."
echo -e "\e[1mRegistry frontend UI \e[m"
echo -e "\e[32m http://${REGISTRY_EXTERNALIP}  \e[m"
echo "or"
echo -e "\e[32m http://registryfe.${DNSDOMAINNAME} \e[m"
echo ""
kubectl get ns kasten-io  > /dev/null 2>&1
HAS_KASTEN=$?
if [ ${HAS_KASTEN} -eq 0 ]; then
KASTENEXTERNALIP=`kubectl -n kasten-io get svc gateway-ext | awk '{print $4}' | tail -n 1`
KASTENINGRESSIP=`kubectl get ingress -n kasten-io --output="jsonpath={.items[*].status.loadBalancer.ingress[*].ip}"`
sa_secret=$(kubectl get serviceaccount k10-k10 -o jsonpath="{.secrets[0].name}" --namespace kasten-io)
kubectl get secret $sa_secret --namespace kasten-io -ojsonpath="{.data.token}{'\n'}" | base64 --decode > k10-k10.token
echo "" >> k10-k10.token
echo -e "\e[1mKasten Dashboard \e[m"
echo -e "\e[32m Open your browser \e[m"
echo -e "\e[32m  http://${KASTENEXTERNALIP}/k10/ \e[m"
echo -e "\e[32m  http://${KASTENINGRESSIP}/k10/# \e[m"
echo -e "\e[32m  https://${KASTENINGRESSIP}/k10/# \e[m"
echo "then input login token"
echo -e "\e[32m cat ./k10-k10.token \e[m"
cat ./k10-k10.token
fi
echo ""
echo -e "\e[1mKubeconfig \e[m"
echo -e "\e[32m ~/.kube/config \e[m"
echo " You can access Kubernetes from your desktop!"
