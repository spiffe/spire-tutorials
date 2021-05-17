#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")"

bash "${DIR}"/create-cluster.sh 
kubectl apply -f "${PARENT_DIR}"/k8s/namespace.yaml
kubectl apply -f "${PARENT_DIR}"/k8s/k8s-workload-registrar-secret.yaml
kubectl apply -f "${PARENT_DIR}"/k8s/spire-server.yaml
kubectl rollout status statefulset/spire-server -n spire

kubectl apply -f "${PARENT_DIR}"/k8s/validation-webhook.yaml
kubectl apply -f "${PARENT_DIR}"/k8s/spire-agent.yaml
kubectl rollout status daemonset/spire-agent -n spire

kubectl apply -f "${PARENT_DIR}"/k8s/workload.yaml
kubectl rollout status deployment/example-workload -n spire
