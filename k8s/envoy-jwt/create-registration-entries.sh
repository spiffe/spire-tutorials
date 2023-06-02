#/bin/bash

set -e

bb=$(tput bold)
nn=$(tput sgr0)

register() {
    kubectl exec -n spire spire-server-0 -c spire-server -- /opt/spire/bin/spire-server entry create $@
}

echo "${bb}Creating registration entry for the backend - auth-server...${nn}"
register \
    -parentID spiffe://example.org/ns/spire/sa/spire-agent \
    -spiffeID spiffe://example.org/ns/default/sa/default/backend \
    -selector k8s:ns:default \
    -selector k8s:sa:default \
    -selector k8s:pod-label:app:backend \
    -selector k8s:container-name:auth-helper

echo "${bb}Creating registration entry for the frontend - auth-server...${nn}"
register \
    -parentID spiffe://example.org/ns/spire/sa/spire-agent \
    -spiffeID spiffe://example.org/ns/default/sa/default/frontend \
    -selector k8s:ns:default \
    -selector k8s:sa:default \
    -selector k8s:pod-label:app:frontend \
    -selector k8s:container-name:auth-helper
