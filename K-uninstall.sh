#!/usr/bin/env bash

helm uninstall k10 --namespace=kasten-io
kubectl delete namespace kasten-io
rm -rf backupadmin.token backupbasic.token backupview.token k10-k10.token nsadmin.token

kubectl get volumesnapshotclass | grep longhorn
retval4=$?
if [ ${retval4} -eq 0 ]; then
	kubectl annotate volumesnapshotclass longhorn \
		k10.kasten.io/is-snapshot-class-
fi

kubectl delete clusterrolebinding backupadmin-rolebinding
kubectl delete clusterrolebinding backupbasic-rolebinding
kubectl delete clusterrolebinding backupview-rolebinding
kubectl delete clusterrolebinding nsadmin-rolebinding
kubectl delete namespace kasten-io-mc

rm -rf k10-*.tgz

if [ -f K1-kasten.sh ]; then
	chmod +x K1-kasten.sh
fi

kubectl get pvc -A
helm repo remove kasten
