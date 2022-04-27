#!/usr/bin/env bash

if [ ! -f ~/.kube/config ] ; then
echo "There is no kubeconfig. exit ..."
exit 0
fi

DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
DNSHOSTIP=`kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'`
DASHBOARD_EXTERNALIP=`kubectl -n kubernetes-dashboard get service dashboard-service-lb| awk '{print $4}' | tail -n 1`
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}" > dashboard.token
echo "" >> dashboard.token
DASHBOARD_FQDN=`kubectl -n kubernetes-dashboard get svc dashboard-service-lb --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4`
REGISTRYHOST=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_host}'`
REIGSTRYPORT=`kubectl -n registry get configmaps pregistry-configmap -o=jsonpath='{.data.pregistry_port}'`
REGISTRYURL=${REGISTRYHOST}:${REIGSTRYPORT}
REGISTRY_EXTERNALIP=`kubectl -n registry get service pregistry-frontend-clusterip | awk '{print $4}' | tail -n 1`
REGISTRY_FQDN=`kubectl -n registry get svc pregistry-frontend-clusterip --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4`
KEYCLOAK_EXTERNALIP=`kubectl -n keycloak get service keycloak  | awk '{print $4}' | tail -n 1`
KEYCLOAK_FQDN=`kubectl -n keycloak get svc keycloak --output="jsonpath={.metadata.annotations}" | jq | grep external | cut -d "\"" -f 4`

echo "*************************************************************************************"
echo "Here is cluster context."
echo -e "\e[1mkubectl config get-contexts \e[m"
kubectl config get-contexts
echo ""
echo "vSphere CSI Driver info"
kubectl get sc | grep vsphere
retvspheredriver=$?
if [ ${retvspheredriver} -eq 0 ]; then
kubectl -n vmware-system-csi describe pod $(kubectl -n vmware-system-csi get pod -l app=vsphere-csi-controller -o custom-columns=:metadata.name)  | grep driver  | grep Image | grep -v ID
fi
echo ""
echo -e "\e[1mmetallb loadbalancer IP address range \e[m"
kubectl -n metallb-system get configmaps config -o jsonpath='{.data.config}'
echo ""
echo -e "\e[1mDNS Server \e[m"
echo -n "DNS Domain Name is "
echo -e "\e[32m${DNSDOMAINNAME} \e[m"
echo -n "DNS DNS IP address is "
echo -e "\e[32m${DNSHOSTIP} \e[m"
echo ""
if [ ! -z ${DASHBOARD_EXTERNALIP} ]; then
echo -e "\e[1mKubernetes dashboard \e[m"
echo -e "\e[32m https://${DASHBOARD_EXTERNALIP}/#/login  \e[m"
echo "or"
echo -e "\e[32m https://${DASHBOARD_FQDN}/#/login \e[m"
echo ""
echo -e "\e[32m login token is cat ./dashboard.token  \e[m"
cat ./dashboard.token
echo ""
fi

kubectl get ns minio-operator > /dev/null 2>&1
retvalminioope=$?
if [ ${retvalminioope} -eq 0 ]; then
MINIOOP_EXTERNALIP=`kubectl -n minio-operator get service console | awk '{print $4}' | tail -n 1`
echo -e "\e[1mMinio Operator \e[m"
echo ""
echo "This is use for adding/delete/manage Minio tenant"
echo ""
echo -e "\e[32m http://minio-console.${DNSDOMAINNAME}:9090/login \e[m"
echo "Or"
echo -e "\e[32m http://${MINIOOP_EXTERNALIP}:9090/login \e[m"
echo ""
echo "Login with JWT token"
echo -e "\e[32m login token is cat ./minio-operator.token  \e[m"
echo ""
sa_secret=$(kubectl get serviceaccount console-sa -o jsonpath="{.secrets[0].name}" --namespace minio-operator)
kubectl get secret $sa_secret --namespace minio-operator -ojsonpath="{.data.token}{'\n'}" | base64 --decode > minio-operator.token
echo "" >> minio-operator.token
cat minio-operator.token
echo ""
echo ""
fi
TENANTNAMESPACE=`kubectl get tenant -A | grep Initialized | cut -d " " -f 1`
if [ ! -z ${TENANTNAMESPACE} ]; then
LOCALHOSTNAMEAPI=${TENANTNAMESPACE}-api.${DNSDOMAINNAME}
LOCALHOSTNAMECONSOLE=${TENANTNAMESPACE}-console.${DNSDOMAINNAME}
LOCALIPADDRAPI=`kubectl -n ${TENANTNAMESPACE} get service minio | awk '{print $4}' | tail -n 1`
LOCALIPADDRCONSOLE=`kubectl -n ${TENANTNAMESPACE} get service ${TENANTNAMESPACE}-console | awk '{print $4}' | tail -n 1`
MCLOGINUSER=`kubectl -n ${TENANTNAMESPACE} get secret ${TENANTNAMESPACE}-user-1 -ojsonpath="{.data."CONSOLE_ACCESS_KEY"}{'\n'}" |base64 --decode`
MCLOGINPASSWORD=`kubectl -n ${TENANTNAMESPACE} get secret ${TENANTNAMESPACE}-user-1 -ojsonpath="{.data."CONSOLE_SECRET_KEY"}{'\n'}" |base64 --decode`

echo -e "\e[1mMinio tenant ${TENANTNAMESPACE}  \e[m"
echo "API endpoint"
echo -e "\e[32m https://${LOCALHOSTNAMEAPI} \e[m"
echo "or"
echo -e "\e[32m https://${LOCALIPADDRAPI} \e[m"
echo "Console"
echo -e "\e[32m https://${LOCALHOSTNAMECONSOLE}:9443  \e[m"
echo "or"
echo -e "\e[32m https://${LOCALIPADDRCONSOLE}:9443  \e[m"
echo ""
echo "Credential"
echo "${MCLOGINUSER} / ${MCLOGINPASSWORD}"
fi
echo ""
if [ ! -z ${REGISTRYURL} ]; then
echo -e "\e[1mRegistry \e[m"
echo -e "\e[1mRegistry URL \e[m"
echo -e "\e[32m http://${REGISTRYURL}  \e[m"
if [ -f /usr/bin/docker ]; then
grep ${REGISTRYURL} /etc/docker/daemon.json
retvaldaemon=$?
if [ ${retvaldaemon} -eq 0 ]; then
echo -e "\e[32m docker was configured. \e[m"
else
echo -e "\e[31m docker was not configured. \e[m"
echo -e "\e[31m You need to set registry setting in docker. \e[m"
fi
fi
 ls -1 /etc/containerd/certs.d/ | grep -v  docker.io | grep ${REGISTRYURL}
retvalcontainerd=$?
 if [ ${retvalcontainerd} -eq 0 ]; then
echo -e "\e[32m containerd was configured. \e[m"
else
echo -e "\e[31m contained was not configured. \e[m"
echo -e "\e[31m You need to set registry setting in containerd. \e[m"
fi
fi
if [ ! -z ${REGISTRY_EXTERNALIP} ]; then
echo -e "\e[1mRegistry frontend UI \e[m"
echo -e "\e[32m http://${REGISTRY_EXTERNALIP}  \e[m"
echo "or"
echo -e "\e[32m http://${REGISTRY_FQDN} \e[m"
echo ""
fi
if [ ! -z ${KEYCLOAK_FQDN} ]; then
echo -e "\e[1mKeycloak  \e[m"
echo -e "\e[32m http://${KEYCLOAK_FQDN}:8080 \e[m"
echo "or"
echo -e "\e[32m http://${KEYCLOAK_EXTERNALIP}:8080  \e[m"
echo ""
echo -n " login credential is "
echo -e "\e[32m admin/admin  \e[m"
echo ""
fi
kubectl get ns kasten-io  > /dev/null 2>&1
HAS_KASTEN=$?
if [ ${HAS_KASTEN} -eq 0 ]; then
KASTENEXTERNALIP=`kubectl -n kasten-io get svc gateway-ext | awk '{print $4}' | tail -n 1`
KASTENFQDNURL=`kubectl -n kasten-io  get svc gateway-ext --output="jsonpath={.metadata.annotations}" | jq | grep external-dns | cut -d "\"" -f 4`
KASTENINGRESSIP=`kubectl get ingress -n kasten-io --output="jsonpath={.items[*].status.loadBalancer.ingress[*].ip}"`
K10INGRESHOST=`kubectl -n kasten-io get ingress k10-ingress --output="jsonpath={.spec.rules[*].host }"`
K10INGRESPATH=`kubectl -n kasten-io get ingress k10-ingress --output="jsonpath={.spec.rules[*].http.paths[*].path }"`
K10INGRESURL="${K10INGRESHOST}${K10INGRESPATH}"
sa_secret=$(kubectl get serviceaccount k10-k10 -o jsonpath="{.secrets[0].name}" --namespace kasten-io)
kubectl get secret $sa_secret --namespace kasten-io -ojsonpath="{.data.token}{'\n'}" | base64 --decode > k10-k10.token
echo "" >> k10-k10.token
sa_secret=$(kubectl get serviceaccount backupadmin -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > backupadmin.token
echo "" >> backupadmin.token
sa_secret=$(kubectl get serviceaccount backupbasic -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > backupbasic.token
echo "" >> backupbasic.token
sa_secret=$(kubectl get serviceaccount backupview -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > backupview.token
echo "" >> backupview.token
sa_secret=$(kubectl get serviceaccount nsadmin -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > nsadmin.token
echo "" >> nsadmin.token
sa_secret=$(kubectl get serviceaccount backup-mc-admin -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > backup-mc-admin.token
echo "" >> backup-mc-admin.token
sa_secret=$(kubectl get serviceaccount backup-mc-user -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > backup-mc-user.token
echo "" >> backup-mc-user.token
echo -e "\e[1mKasten Dashboard \e[m"
echo -e "\e[32m Open your browser \e[m"
echo -e "\e[32m  http://${KASTENFQDNURL}/k10/ \e[m"
echo -e "\e[32m  http://${KASTENEXTERNALIP}/k10/ \e[m"
echo -e "\e[32m  http://${K10INGRESURL} \e[m"
echo -e "\e[32m  https://${K10INGRESURL} \e[m"
echo "then input login token"
echo -e "\e[32m cat ./k10-k10.token \e[m"
cat ./k10-k10.token
fi
echo ""
echo -e "\e[1mKubeconfig \e[m"
echo -e "\e[32m ~/.kube/config \e[m"
echo " You can access Kubernetes from your desktop!"
