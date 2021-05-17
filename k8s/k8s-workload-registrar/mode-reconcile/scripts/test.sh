#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

bold=$(tput bold) || true
norm=$(tput sgr0) || true
red=$(tput setaf 1) || true
green=$(tput setaf 2) || true

set_env() {
    echo "${bold}Setting up reconcile environment...${norm}"  
    "${DIR}"/deploy-scenario.sh
}

cleanup() {
    echo "${bold}Cleaning up...${norm}"
    kind delete cluster --name example-cluster
}

trap cleanup EXIT

cleanup
set_env

NODE_SPIFFE_ID="spiffe://example.org/k8s-workload-registrar/example-cluster/node/example-cluster-control-plane"
AGENT_SPIFFE_ID="spiffe://example.org/agent"
WORKLOAD_SPIFFE_ID="spiffe://example.org/example-workload"

MAX_FETCH_CHECKS=60
FETCH_CHECK_INTERVAL=5

for ((i=0;i<"$MAX_FETCH_CHECKS";i++)); do
    if [[ -n $(kubectl exec -t statefulset/spire-server -n spire -c spire-server -- \
                /opt/spire/bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock \
                    | grep "$NODE_SPIFFE_ID") ]] &&
       [[ -n $(kubectl exec -t daemonset/spire-agent -n spire -- \
                /opt/spire/bin/spire-agent api fetch -socketPath /tmp/spire-agent/public/api.sock  \
                    | grep "$AGENT_SPIFFE_ID") ]] &&
       [[ -n $(kubectl exec -t deployment/example-workload -n spire -- \
                /opt/spire/bin/spire-agent api fetch -socketPath /tmp/spire-agent/public/api.sock  \
                    | grep "$WORKLOAD_SPIFFE_ID") ]]; then
        DONE=1
        break
    fi
    sleep "$FETCH_CHECK_INTERVAL"
done

if [ "${DONE}" -eq 1 ]; then
    echo "${green}Reconcile mode test succeeded.${norm}"
else
    echo "${red}Reconcile mode test failed.${norm}"
    exit 1
fi

exit 0
