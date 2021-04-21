#!/usr/bin/env bash

mkdir ocs-d-ocs-monkey

cd ocs-d-ocs-monkey

git clone git@github.com:openshift/ocs-osd-deployer.git

cd ocs-osd-deployer

oc get ns openshift-storage > /dev/null 2>&1
if [$? -eq 1]]; then
    echo "openshift-storage namespace already exist"
    #exit with non-zero    
    oc delete ns openshift-storage;
    for i in cephobjectstore noobaa cephfilesystem cephblockpool cephcluster storagecluster managedocs
    do 
        oc patch $i $(oc get $i -ojsonpath='{ .items[*].metadata.name }') -p '{"metadata":{"finalizers":[]}}' --type=merge
    done

fi

echo "apiVersion: v1
  kind: Namespace
  metadata:
  labels:
    hive.openshift.io/managed: \"true\"
    managed.openshift.io/storage-pv-quota-exempt: \"true\"
  name: openshift-storage">openshift-storage-ns.yaml

oc create -f openshift-storage-ns.yaml


export IMG=quay.io/dbindra/ocs-osd-deployer:apr20
export BUNDLE_IMG=quay.io/dbindra/ocs-osd-deployer:apr20_bundle

make docker-build IMG=$IMG

docker push $IMG

make manifests

make bundle IMG=$IMG

make bundle-build BUNDLE_IMG=$BUNDLE_IMG

docker push $BUNDLE_IMG

export SERVICE_KEY=0de7fae621aa4b0cc0f6d53002750255


echo "apiVersion: v1
kind: Secret
data:
  PAGERDUTY_KEY: $SERVICE_KEY
metadata:
  name: ocs-converged-dev-pagerduty
  namespace: openshift-storage
">pagerduty-secret.yaml

oc create -f pagerduty-secret.yaml

echo "apiVersion: v1
kind: Secret
data:
  size: 1
metadata:
  name: addon-ocs-converged-dev-parameters
  namespace: openshift-storage
">addon-size-secret.yaml

oc create -f addon-size-secret.yaml

# echo "apiVersion: v1
# data:
#   alertmanager.yaml: ALERTMANAGER_CONFIG
# kind: Secret
# metadata:
#   name: alertmanager-managed-ocs-alertmanager
#   namespace: openshift-storage
# type: Opaque">alertmanager-secret-k8s.yaml

# echo "route:
#     group_wait: 30s
#     group_interval: 5m
#     repeat_interval: 4h
#     receiver: pagerduty
#     routes:
#       - match:
#           severity: warning
#         receiver: pagerduty
# receivers:
#     - name: pagerduty
#       pagerduty_configs:
#         - service_key: $SERVICE_KEY">alertmanager.yaml

# sed "s/ALERTMANAGER_CONFIG/$(cat alertmanager.yaml | base64 -w0)/g" alertmanager-secret-k8s.yaml | kubectl apply -f -

operator-sdk run bundle -n openshift-storage $BUNDLE_IMG