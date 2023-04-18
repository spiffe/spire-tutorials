#/bin/bash

#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXAMPLEDIR="$(dirname "$DIR")"
K8SDIR="$(dirname "$EXAMPLEDIR")"
echo $DIR
echo $EXAMPLEDIR
echo $K8SDIR

DOCKER_IMAGE="envoy-jwt-auth-helper"
SERVICE_VERSION="1.0.0"

echo "Building ${DOCKER_IMAGE}"
(cd $K8SDIR/envoy-jwt-auth-helper; docker build --no-cache --tag ${DOCKER_IMAGE} .)

case $1 in
"minikube") 
	echo "Pushing into minikube"
	minikube image push $DOCKER_IMAGE:latest;;
"kind")
	echo "Load image into kind"
	kind load docker-image $DOCKER_IMAGE:latest;;
*) 
	echo "Image builded successfully";;
esac
