#!/bin/bash

PARENT_DIR="$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")"

kubectl delete -f "${PARENT_DIR}"/k8s/workload.yaml --ignore-not-found

kubectl delete -f "${PARENT_DIR}"/k8s/spire-agent.yaml --ignore-not-found

kubectl delete -f "${PARENT_DIR}"/k8s/spire-server.yaml --ignore-not-found

SPIFFE_ID_CRDS=$(kubectl get spiffeids --no-headers -o custom-columns=":metadata.name" -n spire)
for SPIFFE_ID_CRD in $SPIFFE_ID_CRDS
do
    kubectl patch spiffeid.spiffeid.spiffe.io/"${SPIFFE_ID_CRD}" --type=merge -p '{"metadata":{"finalizers":[]}}' -n spire
    kubectl delete spiffeid "${SPIFFE_ID_CRD}" -n spire --ignore-not-found
done

kubectl patch customresourcedefinition.apiextensions.k8s.io/spiffeids.spiffeid.spiffe.io --type=merge -p '{"metadata":{"finalizers":[]}}'
kubectl delete -f "${PARENT_DIR}"/k8s/spiffeid.spiffe.io_spiffeids.yaml --ignore-not-found


kubectl delete -f "${PARENT_DIR}"/k8s/namespace.yaml --ignore-not-found
