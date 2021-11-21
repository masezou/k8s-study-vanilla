#!/usr/bin/env bash
PGNAMESPACE=postgresql-lb

export POSTGRES_PASSWORD=$(kubectl get secret --namespace ${PGNAMESPACE} postgres-postgresql -o jsonpath="{.data.postgresql-password}" | base64 --decode)
kubectl port-forward --namespace postgresql-lb svc/postgres-postgresql 5432:5432 &
PGPASSWORD="$POSTGRES_PASSWORD" createdb --host 127.0.0.1 -U postgres pgbenchdb
PGPASSWORD="$POSTGRES_PASSWORD" pgbench --host 127.0.0.1 -U postgres  -i pgbenchdb
PGPASSWORD="$POSTGRES_PASSWORD" pgbench --host 127.0.0.1 -U postgres  -c 10 -t 1000  pgbenchdb
