#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")"

if [ -n "${TRAVIS}" ]; then
    minikube stop
    sudo cp -R "${PARENT_DIR}"/k8s/admctrl /var/lib/minikube/certs/
    minikube start --driver=none --bootstrapper=kubeadm --extra-config=apiserver.admission-control-config-file=/var/lib/minikube/certs/admctrl/admission-control.yaml
else
    docker cp "${PARENT_DIR}"/k8s/admctrl minikube:/var/lib/minikube/certs/
    minikube stop
    minikube start \
    --extra-config=apiserver.service-account-signing-key-file=/var/lib/minikube/certs/sa.key \
    --extra-config=apiserver.service-account-key-file=/var/lib/minikube/certs/sa.pub \
    --extra-config=apiserver.service-account-issuer=api \
    --extra-config=apiserver.service-account-api-audiences=api,spire-server \
    --extra-config=apiserver.authorization-mode=Node,RBAC \
    --extra-config=apiserver.admission-control-config-file=/var/lib/minikube/certs/admctrl/admission-control.yaml
fi

kubectl apply -f "${PARENT_DIR}"/k8s/namespace.yaml
kubectl apply -f "${PARENT_DIR}"/k8s/k8s-workload-registrar-secret.yaml
kubectl apply -f "${PARENT_DIR}"/k8s/spire-server.yaml
kubectl rollout status statefulset/spire-server -n spire

kubectl apply -f "${PARENT_DIR}"/k8s/validation-webhook.yaml
kubectl apply -f "${PARENT_DIR}"/k8s/spire-agent.yaml
kubectl rollout status daemonset/spire-agent -n spire

kubectl apply -f "${PARENT_DIR}"/k8s/workload.yaml
kubectl rollout status deployment/example-workload -n spire
