#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

# Creates Envoy-X509 scenario
bash "${K8SDIR}"/envoy-x509/scripts/set-env.sh
