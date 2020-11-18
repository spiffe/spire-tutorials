#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true

restart_deployments() {
    kubectl scale deployment backend --replicas=0
    kubectl scale deployment backend --replicas=1

    kubectl scale deployment frontend --replicas=0
    kubectl scale deployment frontend --replicas=1

    kubectl scale deployment frontend-2 --replicas=0
    kubectl scale deployment frontend-2 --replicas=1
}

wait_for_envoy() {
    # wait until deployments are completed and Envoy is ready
    LOGLINE="DNS hosts have changed for backend-envoy"

    for ((i=0;i<30;i++)); do
        if ! kubectl rollout status deployment/backend; then
            sleep 1
            continue
        fi
        if ! kubectl rollout status deployment/frontend; then
            sleep 1
            continue
        fi
        if ! kubectl rollout status deployment/frontend-2; then
            sleep 1
            continue
        fi
        if ! kubectl logs --tail=300 --selector=app=frontend -c envoy | grep -qe "${LOGLINE}" ; then
            sleep 5
            echo "Waiting until Envoy is ready..."
            continue
        fi
        echo "Workloads ready."
        WK_READY=1
        break
    done
    if [ -z "${WK_READY}" ]; then
        echo "${red}Timed out waiting for workloads to be ready.${nn}"
        exit 1
    fi
}

#Creates k8s Quickstart scenario
bash "${EXAMPLEDIR}"/scripts/pre-set-env.sh > /dev/null

echo "${bb}Applying SPIRE Envoy X509 configuration...${nn}"
# Updates resources for the backend and frontend
kubectl apply -k "${EXAMPLEDIR}"/k8s/. > /dev/null
bash "${EXAMPLEDIR}"/create-registration-entries.sh > /dev/null

#Restarts all deployments to pickup the new configurations
restart_deployments > /dev/null

echo "${bb}Waiting until deployments and Envoy are ready...${nn}"
wait_for_envoy > /dev/null

echo "${bb}X.509 Environment creation completed.${nn}"
