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

trap clean-env EXIT

echo "${bb}Preparing environment...${nm}"
clean-env
bash "${DIR}"/scripts/pre-set-env.sh > /dev/null

echo "${bb}Applying SPIRE Envoy JWT configuration...${nn}"
kubectl delete deployment backend > /dev/null
kubectl delete deployment frontend > /dev/null
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
    echo "${red}Timed out waiting for workloads to be running.${nn}"
    exit 1
fi

# If balance is part of the response, then the request was accepted by the backend and token was valid.
BALANCE_LINE="Your current balance is 10.95"
if curl -s $(minikube service frontend --url) | grep -qe "$BALANCE_LINE"; then
   echo "${green}Success${nn}"
   exit 0
fi

echo "${red}Failed! Request did not make it through the proxies.${nn}".
exit 1
