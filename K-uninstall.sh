#!/usr/bin/env bash

helm uninstall k10 --namespace=kasten-io
kubectl delete namespace kasten-io
rm -rf backupadmin.token  backupbasic.token  backupview.token k10-k10.token  nsadmin.token
kubectl get volumesnapshotclass | grep csi-hostpath-snapclass
retval1=$?
if [ ${retval1} -eq 0 ]; then
kubectl annotate volumesnapshotclass csi-hostpath-snapclass \
    k10.kasten.io/is-snapshot-class-
fi

kubectl get volumesnapshotclass | grep csi-rbdplugin-snapclass
retval2=$?
if [ ${retval2} -eq 0 ]; then
kubectl annotate volumesnapshotclass csi-rbdplugin-snapclass \
    k10.kasten.io/is-snapshot-class-
fi

kubectl get volumesnapshotclass | grep longhorn
retval4=$?
if [ ${retval4} -eq 0 ]; then
kubectl annotate volumesnapshotclass longhorn \
    k10.kasten.io/is-snapshot-class-
fi

kubectl get volumesnapshotclass | grep csi-cstor-snapshotclass
retval7=$?
if [ ${retval7} -eq 0 ]; then
kubectl annotate volumesnapshotclass csi-cstor-snapshotclass \
    k10.kasten.io/is-snapshot-class-
fi
kubectl delete namespace kasten-io-mc

if [ -f K1-kasten.sh ]; then
chmod +x K1-kasten.sh
fi

kubectl get pvc -A
helm repo remove kasten
