#!/usr/bin/env bash

./0-minio.sh
./1-tools.sh
./2-buildk8s-lnx.sh
./3-configk8s.sh
./4-dns.sh
./5-csi-storage.sh
./K0-kasten-tools.sh