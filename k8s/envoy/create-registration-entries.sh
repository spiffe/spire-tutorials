#/bin/bash

set -e

bb=$(tput bold)
nn=$(tput sgr0)

echo "${bb}Creating registration entry for the backend - envoy...${nn}"
kubectl exec -n spire spire-server-0 -- \
    /opt/spire/bin/spire-server entry create \
    -parentID spiffe://example.org/ns/spire/sa/spire-agent \
    -spiffeID spiffe://example.org/ns/default/sa/default/backend \
    -selector k8s:ns:default \
    -selector k8s:sa:default \
    -selector k8s:pod-label:app:backend \
    -selector k8s:container-name:envoy

echo "${bb}Creating registration entry for the frontend - envoy...${nn}"
kubectl exec -n spire spire-server-0 -- \
    /opt/spire/bin/spire-server entry create \
    -parentID spiffe://example.org/ns/spire/sa/spire-agent \
    -spiffeID spiffe://example.org/ns/default/sa/default/frontend \
    -selector k8s:ns:default \
    -selector k8s:sa:default \
    -selector k8s:pod-label:app:frontend \
    -selector k8s:container-name:envoy

echo "${bb}Creating registration entry for the frontend - envoy...${nn}"
kubectl exec -n spire spire-server-0 -- \
    /opt/spire/bin/spire-server entry create \
    -parentID spiffe://example.org/ns/spire/sa/spire-agent \
    -spiffeID spiffe://example.org/ns/default/sa/default/frontend-2 \
    -selector k8s:ns:default \
    -selector k8s:sa:default \
    -selector k8s:pod-label:app:frontend-2 \
    -selector k8s:container-name:envoy

echo "${bb}Listing created registration entries...${nn}"
kubectl exec -n spire spire-server-0 -- /opt/spire/bin/spire-server entry show