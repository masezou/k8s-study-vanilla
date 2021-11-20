#!/usr/bin/env bash

helm uninstall k10 --namespace=kasten-io
kubectl delete namespace kasten-io
rm -rf backupadmin.token  backupbasic.token  backupview.token k10-k10.token  nsadmin.token
kubectl get pvc -A
