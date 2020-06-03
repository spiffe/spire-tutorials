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
        echo "${bold}SPIRE Agent ready.${nn}"
        RUNNING=1
        break
    done
    if [ ! -n "${RUNNING}" ]; then
        echo "${red}Timed out waiting for SPIRE Agent to be running.${nn}"
        exit 1
    fi
}

echo "${bb}Creates all the resources needed to the SPIRE Server and SPIRE Agent to be available in the cluster.${nn}"
kubectl apply -k ${K8SDIR}/quickstart/.

echo "${bb}Waiting until SPIRE Agent is running${nn}"
wait_for_agent

echo "${bb}Creates registration entries.${nn}"
bash ${K8SDIR}/quickstart/create-node-registration-entry.sh > /dev/null

echo "${green}SPIRE resources creation completed.${nn}"
