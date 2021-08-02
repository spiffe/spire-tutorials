#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

bold=$(tput bold) || true
norm=$(tput sgr0) || true
red=$(tput setaf 1) || true
green=$(tput setaf 2) || true

set_env() {
    echo "${bold}Setting up webhook environment...${norm}"  
    "${DIR}"/scripts/deploy-scenario.sh > /dev/null
}

cleanup() {
    echo "${bold}Cleaning up...${norm}"
    "${DIR}"/scripts/delete-scenario.sh > /dev/null
}

trap cleanup EXIT

cleanup
set_env

NODE_SPIFFE_ID="spiffe://example.org/k8s-workload-registrar/demo-cluster/node"
AGENT_SPIFFE_ID="spiffe://example.org/ns/spire/sa/spire-agent"
WORKLOAD_SPIFFE_ID="spiffe://example.org/ns/spire/sa/default"

MAX_FETCH_CHECKS=60
FETCH_CHECK_INTERVAL=5

for ((i=0;i<"$MAX_FETCH_CHECKS";i++)); do
    if [[ -n $(kubectl exec -t statefulset/spire-server -n spire -c spire-server -- \
                /opt/spire/bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock \
                    | grep "$NODE_SPIFFE_ID") ]] &&
       [[ -n $(kubectl exec -t daemonset/spire-agent -n spire -c spire-agent -- \
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
    exit 0
else
    echo "${red}Webhook mode test failed.${norm}"
    exit 1
fi
