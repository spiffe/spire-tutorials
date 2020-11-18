#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true

restart_deployment() {
    kubectl scale deployment backend --replicas=0

    # Let's be sure that there is no pod running before starting the new pod
    for ((i=0;i<30;i++)); do
        if ! kubectl get pod --selector=app=backend 2>&1 | grep -qe "No resources found in default namespace." ; then
            sleep 5
            echo "Waiting until backend pod is terminated..."
            continue
        fi
        echo "Backend pod is terminated. Let's re-start it."
        POD_TERMINATED=1
        break
    done
    if [ -z "${POD_TERMINATED}" ]; then
        echo "${red}Timed out waiting for pods to be terminated.${nn}"
        exit 1
    fi

    kubectl scale deployment backend --replicas=1
}

wait_for_envoy() {
    # waits until deployments are completed and Envoy ready
    kubectl rollout status deployment/backend --timeout=60s

    LOGLINE="all dependencies initialized. starting workers"
    LOGLINE2="membership update for TLS cluster backend added 1 removed 1"
    for ((i=0;i<30;i++)); do
        if ! kubectl logs --tail=100 --selector=app=backend -c envoy | grep -qe "${LOGLINE}" ; then
            sleep 5
            echo "Waiting until backend envoy instance is ready..."
            continue
        fi
        if ! kubectl logs --tail=30 --selector=app=frontend -c envoy | grep -qe "${LOGLINE2}" ; then
            sleep 5
            echo "Waiting until frontend envoy instance is in sync with the backend envoy..."
            continue
        fi
        echo "${bb}Workloads ready.${nn}"
        WK_READY=1
        break
    done
    if [ -z "${WK_READY}" ]; then
        echo "${red}Timed out waiting for workloads to be ready.${nn}"
        exit 1
    fi
}

# Creating Envoy-x509 scenario
bash "${EXAMPLEDIR}"/scripts/pre-set-env.sh > /dev/null

echo "${bb}Applying SPIRE Envoy OPA configuration...${nn}"
kubectl apply -k "${EXAMPLEDIR}"/k8s/. > /dev/null

echo "${bb}Restarting backend pod...${nn}"
restart_deployment > /dev/null

echo "${bb}Waiting until deployments and Envoy are ready...${nn}"
wait_for_envoy

echo "${bb}Envoy OPA Environment creation completed.${nn}"
