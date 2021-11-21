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
REGISTRY_EXTERNALIP=`kubectl -n registry get service pregistry-frontend-clusterip | awk '{print $4}' | tail -n 1`

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
echo -e "\e[32m https://${REGISTRY_EXTERNALIP}  \e[m"
echo "or"
echo -e "\e[32m https://registryfe.${DNSDOMAINNAME} \e[m"
echo ""
KUBECONFIG=`ls *_kubeconfig`
echo -e "\e[1mKubeconfig \e[m"
echo -e "\e[32m${KUBECONFIG} \e[m"
echo " Copy ${KUBECONFIG} to HOME/.kube/config in your Windows/Mac/Linux desktop"
echo " You can access Kubernetes from your desktop!"
