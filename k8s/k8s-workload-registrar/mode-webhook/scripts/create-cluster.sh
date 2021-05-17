#!/bin/bash

PARENT_DIR="$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")"
sed -i.bak "s#WEBHOOKDIR#${PARENT_DIR}#g" "${PARENT_DIR}"/kind-config.yaml

rm "${PARENT_DIR}"/kind-config.yaml.bak
kind create cluster --name example-cluster --config "${PARENT_DIR}"/kind-config.yaml
