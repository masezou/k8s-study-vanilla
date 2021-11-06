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
cd ..

echo ""
echo "*************************************************************************************"
echo "Next Step"
echo "kubectl -n pacman get svc"
echo "http://EXTERNAL-IP/"
echo ""

chmod -x P-pacman.sh
