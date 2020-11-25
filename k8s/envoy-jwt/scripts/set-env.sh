#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true

restart_deployments() {
    # Delete pods so they are re run using the new configurations
    kubectl scale deployment backend --replicas=0
    kubectl scale deployment frontend --replicas=0
    kubectl scale deployment frontend-2 --replicas=0

    # Let's be sure that there is no pod running before starting the new pods
    for ((i=0;i<30;i++)); do
        if ! kubectl get pods 2>&1 | grep -qe "No resources found in default namespace." ; then
            sleep 5
            echo "Waiting until pods are terminated..."
            continue
        fi
        echo "Pods are terminated. Let's re-start them."
        POD_TERMINATED=1
        break
    done
    if [ -z "${POD_TERMINATED}" ]; then
        echo "${red}Timed out waiting for pods to be terminated.${nn}"
        exit 1
    fi

    # Restart all pods
    kubectl scale deployment backend --replicas=1
    kubectl scale deployment frontend --replicas=1
    kubectl scale deployment frontend-2 --replicas=1
}


wait_for_envoy() {
    # wait until deployments are completed
    kubectl rollout status deployment/backend --timeout=60s
    kubectl rollout status deployment/frontend --timeout=60s
    kubectl rollout status deployment/frontend-2 --timeout=60s

    # wait until Envoy is ready
    LOGLINE="all dependencies initialized. starting workers"
    LOGLINE2="DNS hosts have changed for backend-envoy"
    for ((i=0;i<30;i++)); do
        if ! kubectl logs --tail=300 --selector=app=frontend -c envoy | grep -qe "${LOGLINE}" ; then
            sleep 5
            echo "Waiting until Envoy is ready..."
            continue
        fi
        if ! kubectl logs --tail=100 --selector=app=frontend -c envoy | grep -qe "${LOGLINE2}" ; then
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

echo "${bb}Creating Envoy-x509 scenario...${nn}"
bash "${EXAMPLEDIR}"/scripts/pre-set-env.sh > /dev/null

echo "${bb}Applying SPIRE Envoy JWT configuration...${nn}"
kubectl apply -k "${EXAMPLEDIR}"/k8s/. > /dev/null
bash "${EXAMPLEDIR}"/create-registration-entries.sh > /dev/null

# Updates resources for frontend-2
kubectl apply -k "${EXAMPLEDIR}"/k8s/frontend-2/. > /dev/null
bash "${EXAMPLEDIR}"/k8s/frontend-2/create-registration-entry.sh > /dev/null

# Restarts all deployments to pickup the new configurations
restart_deployments > /dev/null

echo "${bb}Waiting until deployments and Envoy are ready...${nn}"
wait_for_envoy > /dev/null

echo "${bb}Envoy JWT Environment creation completed.${nn}"
