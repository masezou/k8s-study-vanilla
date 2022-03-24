#!/usr/bin/env bash
source /etc/profile.d/krew.sh

#########################################################
kubectl krew install ctx
kubectl krew install ns
kubectl krew install iexec
kubectl krew install status
kubectl krew install neat
kubectl krew install view-secret
kubectl krew install images
kubectl krew install rolesum
kubectl krew install open-svc

kubectl krew install tree
kubectl krew install exec-as
kubectl krew install modify-secret
kubectl krew install view-serviceaccount-kubeconfig
kubectl krew install get-all
kubectl krew install node-shell
kubectl krew install ca-cert
kubectl krew install who-can

kubectl krew install outdated
kubectl krew install df-pv
kubectl krew install resource-capacity
kubectl krew install fleet
kubectl krew install prompt

kubectl krew list
