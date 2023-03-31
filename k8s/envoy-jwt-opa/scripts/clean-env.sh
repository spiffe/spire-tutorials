#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
green=$(tput setaf 2) || true

echo "${bb}Deleting new backend resources...${nn}"
kubectl delete -k "${EXAMPLEDIR}"/k8s/. --ignore-not-found

echo "${bb}Deleting pre-set resources...${nn}"
bash "${K8SDIR}"/envoy-jwt/scripts/clean-env.sh > /dev/null

echo "${green}Cleaning completed.${nn}"
