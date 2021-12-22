#!/usr/bin/env bash

CONTEXT=`kubectl config get-contexts -o=name`
CLUSTERNAME=`kubectl config get-clusters | tail -n 1`
k10multicluster setup-primary --context=${CONTEXT} --name=${CLUSTERNAME} 
cat <<EOF | kubectl apply -f -
apiVersion: auth.kio.kasten.io/v1alpha1
kind: K10ClusterRoleBinding
metadata:
  name: admin-all-clusters
  namespace: kasten-io-mc
spec:
  clusters:
  - selector: ""
  k10ClusterRole: k10-multi-cluster-admin
  subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: system:serviceaccount:kasten-io:k10-k10
EOF

chmod -x $0
