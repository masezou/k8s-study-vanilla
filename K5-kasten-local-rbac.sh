#!/usr/bin/env bash

# Configure default users
#Backup Admin
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backupadmin
  namespace: default
EOF
sa_secret=$(kubectl get serviceaccount backupadmin -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > backupadmin.token
echo "" >> backupadmin.token
kubectl get serviceaccounts
kubectl get serviceaccounts backupadmin -o yaml

kubectl create clusterrolebinding backupadmin-rolebinding --clusterrole=k10-admin  --serviceaccount=default:backupadmin

#Backup Basic
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backupbasic
  namespace: default
EOF
sa_secret=$(kubectl get serviceaccount backupbasic -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > backupbasic.token
echo "" >> backupbasic.token

kubectl create clusterrolebinding backupbasic-rolebinding --clusterrole=k10-basic  --serviceaccount=default:backupbasic

#Backup View
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backupview
  namespace: default
EOF
sa_secret=$(kubectl get serviceaccount backupview -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > backupview.token
echo "" >> backupview.token

kubectl create clusterrolebinding backupview-rolebinding --clusterrole=k10-config-view  --serviceaccount=default:backupview

#NS Admin
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nsadmin
  namespace: default
EOF
sa_secret=$(kubectl get serviceaccount nsadmin -o jsonpath="{.secrets[0].name}")
kubectl get secret $sa_secret  -ojsonpath="{.data.token}{'\n'}" | base64 --decode > nsadmin.token
echo "" >> nsadmin.token

kubectl create clusterrolebinding nsadmin-rolebinding --clusterrole=k10-ns-admin  --serviceaccount=default:nsadmin --namespace wordpress-sample

echo ""
echo "k10 accounts were configured"
echo ""

chmod -x ./K5-kasten-local-rbac.sh
