#!/usr/bin/env bash
echo -e "\e[32mStarting $0 ....\e[m"
# Copyright (c) 2022 masezou. All rights reserved.

KANISTERVER=0.98.0

##################################################

#if [ -z ${KANISTERVER} ]; then
#KANISTERVER=$(kubectl -n kasten-io get deployments.apps catalog-svc -o json | grep kanister-tools | cut -d "/" -f 2 | cut -d ":" -f 2 | cut -d "-" -f 2 | cut -d "\"" -f 1)
#fi

echo "Kanister version: ${KANISTERVER}"

#Install blueprint
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/mongodb/blueprint-v2/mongo-blueprint.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/mysql/blueprint-v2/mysql-blueprint.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/postgresql/blueprint-v2/postgres-blueprint.yaml
kubectl --namespace kasten-io apply -f \
    https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/postgresql-ha/hook-blueprint/postgres-ha-hook.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/etcd/etcd-in-cluster/k8s/etcd-incluster-blueprint.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/maria/blueprint-v2/maria-blueprint.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/mssql/blueprint-v2/mssql-blueprint.yaml

echo "*************************************************************************************"
echo "Pre-defined blueprints were configured"
kubectl -n kasten-io get blueprints
echo ""

chmod -x $0
