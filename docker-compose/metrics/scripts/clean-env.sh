#/bin/bash

set -e

PARENT_DIR="$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")"

norm=$(tput sgr0) || true
green=$(tput setaf 2) || true

docker-compose -f "${PARENT_DIR}"/docker-compose.yaml down

echo "${green}Cleaning completed.${norm}"
