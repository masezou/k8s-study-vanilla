#!/usr/bin/env bash

CONTEXT=`kubectl config get-contexts -o=name`
CLUSTERNAME=`kubectl config get-clusters | tail -n 1`
k10multicluster setup-primary --context=${CONTEXT} --name=${CLUSTERNAME} 


chmod -x $0
