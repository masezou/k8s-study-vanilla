#!/usr/bin/env bash

kubectl --namespace=kasten-io delete deployment prometheus-server
helm repo update && \
    helm get values k10 --output yaml --namespace=kasten-io > k10_val.yaml && \
    helm upgrade k10 kasten/k10 --namespace=kasten-io -f k10_val.yaml
