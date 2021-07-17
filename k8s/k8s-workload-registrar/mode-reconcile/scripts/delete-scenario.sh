#!/bin/bash

PARENT_DIR="$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")"

kubectl delete -f "${PARENT_DIR}"/k8s/workload.yaml --ignore-not-found

kubectl delete -f "${PARENT_DIR}"/k8s/spire-agent.yaml --ignore-not-found

kubectl delete -f "${PARENT_DIR}"/k8s/spire-server.yaml --ignore-not-found
kubectl delete -f "${PARENT_DIR}"/k8s/namespace.yaml --ignore-not-found
