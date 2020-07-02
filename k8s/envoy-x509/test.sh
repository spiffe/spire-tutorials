#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true
green=$(tput setaf 2) || true

clean-env() {
    echo "${bb}Cleaning up...${nn}"
    bash "${DIR}"/scripts/clean-env.sh > /dev/null
}

LOGLINE="Node attestation request completed"
wait_for_agent() {
    for ((i=0;i<120;i++)); do
        if ! kubectl -nspire rollout status daemonset/spire-agent; then
            sleep 1
            continue
        fi
        if ! kubectl -nspire logs statefulset/spire-server -c spire-server | grep -e "$LOGLINE" ; then
            sleep 1
            continue
        fi
        echo "${bold}SPIRE Agent ready.${nn}"
        RUNNING=1
        break
    done
    if [ ! -n "${RUNNING}" ]; then
        echo "${red}Timed out waiting for SPIRE Agent to be ready.${nn}"
        exit 1
    fi
}

trap clean-env EXIT

echo "${bb}Create SPIRE resources...${nm}"
clean-env
bash "${DIR}"/scripts/pre-set-env.sh

echo "${bb}Enables SDS support on SPIRE Agent.${nn}"
kubectl apply -f "${DIR}"/spire-agent-configmap.yaml > /dev/null
kubectl -n spire delete pod $(kubectl -n spire get pods --selector=app=spire-agent --output=jsonpath="{..metadata.name}") > /dev/null
wait_for_agent > /dev/null

echo "${bb}Applying SPIRE Envoy x509 resources...${nn}"
kubectl apply -k "${DIR}"/k8s/. > /dev/null
bash "${DIR}"/create-registration-entries.sh > /dev/null

# wait until deployments are completed and Envoy ready
LOGLINE="DNS hosts have changed for backend-envoy"
for ((i=0;i<120;i++)); do
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
    if ! kubectl logs --tail=100 --selector=app=frontend -c envoy | grep -qe "${LOGLINE}" ; then
        sleep 5
        echo "Waiting until Envoy is ready.."
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

# If balance is part of the response, then the request reached the backend service.
BALANCE_LINE="Your current balance is 10.95"
if curl -s $(minikube service frontend --url) | grep -qe "$BALANCE_LINE"; then
   echo "${green}Success${nn}"
   exit 0
fi

echo "${red}Failed! Request did not make it through the proxies.${nn}".
exit 1
