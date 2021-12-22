#!/usr/bin/env bash

#Install blueprint
kubectl --namespace kasten-io apply -f \
    https://raw.githubusercontent.com/kanisterio/kanister/master/examples/stable/mongodb/blueprint-v2/mongo-blueprint.yaml
kubectl --namespace kasten-io apply -f \
    https://raw.githubusercontent.com/kanisterio/kanister/master/examples/stable/mysql/blueprint-v2/mysql-blueprint.yaml
kubectl --namespace kasten-io apply -f \
    https://raw.githubusercontent.com/kanisterio/kanister/master/examples/stable/postgresql/blueprint-v2/postgres-blueprint.yaml
kubectl --namespace kasten-io apply -f \
    https://raw.githubusercontent.com/kanisterio/kanister/master/examples/stable/elasticsearch/blueprint-v2/elasticsearch-blueprint.yaml
kubectl --namespace kasten-io apply -f \
    https://raw.githubusercontent.com/kanisterio/kanister/master/examples/etcd/etcd-in-cluster/k8s/etcd-incluster-blueprint.yaml
kubectl --namespace kasten-io apply -f \
    https://raw.githubusercontent.com/kanisterio/kanister/master/examples/stable/couchbase/blueprint-v2/couchbase-blueprint.yaml
kubectl --namespace kasten-io apply -f \
    https://raw.githubusercontent.com/kanisterio/kanister/master/examples/stable/foundationdb/blueprint-v2/foundationdb-blueprint.yaml
kubectl --namespace kasten-io apply -f \
    https://raw.githubusercontent.com/kanisterio/kanister/master/examples/stable/maria/blueprint-v2/maria-blueprint.yaml

#kubectl --namespace kafka-test apply -f \
#     https://raw.githubusercontent.com/kanisterio/kanister/master/examples/kafka/adobe-s3-connector/kafka-blueprint.yaml

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

# Mongodb
cat <<'EOF' | kubectl --namespace=kasten-io create -f -
apiVersion: cr.kanister.io/v1alpha1
kind: Blueprint
metadata:
  name: mongo-hooks
actions:
  backupPrehook:
    phases:
    - func: KubeExec
      name: lockMongo
      objects:
        mongoDbSecret:
          kind: Secret
          name: '{{ index .Object.metadata.labels "app.kubernetes.io/instance" }}'
          namespace: '{{ .Deployment.Namespace }}'
      args:
        namespace: "{{ .Deployment.Namespace }}"
        pod: "{{ index .Deployment.Pods 0 }}"
        container: mongodb
        command:
        - bash
        - -o
        - errexit
        - -o
        - pipefail
        - -c
        - |
          export MONGODB_ROOT_PASSWORD='{{ index .Phases.lockMongo.Secrets.mongoDbSecret.Data "mongodb-root-password" | toString }}'
          mongo --authenticationDatabase admin -u root -p "${MONGODB_ROOT_PASSWORD}" --eval="db.fsyncLock()"
  backupPosthook:
    phases:
    - func: KubeExec
      name: unlockMongo
      objects:
        mongoDbSecret:
          kind: Secret
          name: '{{ index .Object.metadata.labels "app.kubernetes.io/instance" }}'
          namespace: '{{ .Deployment.Namespace }}'
      args:
        namespace: "{{ .Deployment.Namespace }}"
        pod: "{{ index .Deployment.Pods 0 }}"
        container: mongodb
        command:
        - bash
        - -o
        - errexit
        - -o
        - pipefail
        - -c
        - |
          export MONGODB_ROOT_PASSWORD='{{ index .Phases.unlockMongo.Secrets.mongoDbSecret.Data "mongodb-root-password" | toString }}'
          mongo --authenticationDatabase admin -u root -p "${MONGODB_ROOT_PASSWORD}" --eval="db.fsyncUnlock()"
EOF


echo "*************************************************************************************"
echo "Pre-defined blueprints were configured"
echo ""

chmod -x $0
