#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"


bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true
green=$(tput setaf 2) || true

LOGLINE="Node attestation request completed"
wait_for_agent() {
    for ((i=0;i<120;i++)); do
        if ! kubectl -nspire rollout status statefulset/spire-server; then
            sleep 1
            continue
        fi
        if ! kubectl -nspire rollout status daemonset/spire-agent; then
            sleep 1
            continue
        fi
        if ! kubectl -nspire logs statefulset/spire-server -c spire-server | grep -e "$LOGLINE" ; then
            sleep 1
            continue
        fi
        echo "${bold}SPIRE Agent running.${nn}"
        RUNNING=1
        break
    done
    if [ ! -n "${RUNNING}" ]; then
        echo "${red}Timed out waiting for SPIRE Agent to be running.${nn}"
        exit 1
    fi
}

echo "${bb}Creates all the resources needed for the SPIRE Server and SPIRE Agent to be available in the cluster.${nn}"
kubectl apply -k "${K8SDIR}"/quickstart/.

echo "${bb}Waiting until SPIRE Agent is running${nn}"
wait_for_agent

echo "${bb}Enables SDS support on SPIRE Agent.${nn}"
kubectl apply -f "${K8SDIR}"/envoy-x509/spire-agent-configmap.yaml
kubectl -n spire delete pod $(kubectl -n spire get pods --selector=app=spire-agent --output=jsonpath="{..metadata.name}")
wait_for_agent

echo "${bb}Create Envoy-x509 scenario.${nn}"
kubectl apply -k "${K8SDIR}"/envoy-x509/k8s/.
echo "${bb}Creates registration entries.${nn}"
bash "${K8SDIR}"/quickstart/create-node-registration-entry.sh > /dev/null
bash "${K8SDIR}"/envoy-x509/create-registration-entries.sh > /dev/null

echo "${green}Environment creation completed.${nn}"
