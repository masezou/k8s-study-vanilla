#!/usr/bin/env bash

helm uninstall k10 --namespace=kasten-io
kubectl delete namespace kasten-io
kubectl get pvc -A
