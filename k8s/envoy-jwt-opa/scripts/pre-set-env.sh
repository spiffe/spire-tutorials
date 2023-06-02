#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"

#Creates Envoy-JWT scenario
bash "${K8SDIR}"/envoy-jwt/scripts/set-env.sh

