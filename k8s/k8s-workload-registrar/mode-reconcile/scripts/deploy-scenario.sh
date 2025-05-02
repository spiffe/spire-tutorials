#!/bin/bash

PARENT_DIR="$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")"

kubectl apply -f "${PARENT_DIR}"/k8s/namespace.yaml
kubectl apply -f "${PARENT_DIR}"/k8s/spire-server.yaml
kubectl rollout status statefulset/spire-server -n spire

kubectl apply -f "${PARENT_DIR}"/k8s/spire-agent.yaml
kubectl rollout status daemonset/spire-agent -n spire

kubectl apply -f "${PARENT_DIR}"/k8s/workload.yaml
kubectl rollout status deployment/example-workload -n spire
