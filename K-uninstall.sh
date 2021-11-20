#!/usr/bin/env bash

helm uninstall k10 --namespace=kasten-io
kubectl delete namespace kasten-io
rm -rf k10-k10.token
kubectl get pvc -A
