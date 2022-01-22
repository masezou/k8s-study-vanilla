#!/usr/bin/env bash

### Install command check ####
if type "kubectl" > /dev/null 2>&1
then
    echo "kubectl was already installed"
else
    echo "kubectl was not found. Please install kubectl and re-run"
    exit 255
fi

git clone https://github.com/saintdle/pacman-tanzu
cd pacman-tanzu/
bash ./pacman-install.sh
kubectl get pvc -n pacman
kubectl get svc -n pacman

DNSDOMAINNAME=`kubectl -n external-dns get deployments.apps  --output="jsonpath={.items[*].spec.template.spec.containers }" | jq |grep rfc2136-zone | cut -d "=" -f 2 | cut -d "\"" -f 1`
kubectl -n pacman annotate service pacman external-dns.alpha.kubernetes.io/hostname=pacman.${DNSDOMAINNAME}

sleep 10
host pacman.${DNSDOMAINNAME}
retvaldns=$?

cd ..

echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "kubectl -n pacman get svc"
echo "http://EXTERNAL-IP/"
if [ ${retvaldns} -eq 0 ]; then 
echo "or"
echo "http://pacman.${DNSDOMAINNAME}/"
fi
echo ""

chmod -x P-pacman.sh
