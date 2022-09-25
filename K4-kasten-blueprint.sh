#!/usr/bin/env bash
echo -e "\e[32mStarting $0 ....\e[m"
# Copyright (c) 2022 masezou. All rights reserved.

KANISTERVER=$(kubectl -n kasten-io get deployments.apps catalog-svc -o json | grep kanister-tools | cut -d "/" -f 3 | cut -d ":" -f 2 | cut -d "-" -f 2 | cut -d "\"" -f 1)

echo "Kanister version: ${KANISTERVER}"

#Install blueprint
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/mongodb/blueprint-v2/mongo-blueprint.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/mysql/blueprint-v2/mysql-blueprint.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/postgresql/blueprint-v2/postgres-blueprint.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/etcd/etcd-in-cluster/k8s/etcd-incluster-blueprint.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/maria/blueprint-v2/maria-blueprint.yaml
kubectl --namespace kasten-io apply -f \
	https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/mssql/blueprint-v2/mssql-blueprint.yaml

#kubectl --namespace kafka-test apply -f \
#     https://raw.githubusercontent.com/kanisterio/kanister/${KANISTERVER}/examples/kafka/adobe-s3-connector/kafka-blueprint.yaml

# Application-Consistent Backups

# PostgreSQL
cat <<'EOF' | kubectl --namespace=kasten-io create -f -
apiVersion: cr.kanister.io/v1alpha1
kind: Blueprint
metadata:
  name: postgresql-hooks
actions:
  backupPrehook:
    phases:
    - func: KubeExec
      name: makePGCheckPoint
      args:
        namespace: "{{ .StatefulSet.Namespace }}"
        pod: "{{ index .StatefulSet.Pods 0 }}"
        container: postgres-postgresql
        command:
        - bash
        - -o
        - errexit
        - -o
        - pipefail
        - -c
        - |
          PGPASSWORD=${POSTGRES_PASSWORD} psql -U $POSTGRES_USER -c "select pg_start_backup('app_cons');"
  backupPosthook:
    phases:
    - func: KubeExec
      name: afterPGBackup
      args:
        namespace: "{{ .StatefulSet.Namespace }}"
        pod: "{{ index .StatefulSet.Pods 0 }}"
        container: postgres-postgresql
        command:
        - bash
        - -o
        - errexit
        - -o
        - pipefail
        - -c
        - |
          PGPASSWORD=${POSTGRES_PASSWORD} psql -U $POSTGRES_USER -c "select pg_stop_backup();"
EOF

echo "*************************************************************************************"
echo "Pre-defined blueprints were configured"
kubectl -n kasten-io get blueprints
echo ""

chmod -x $0
