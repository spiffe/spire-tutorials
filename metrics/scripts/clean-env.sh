#/bin/bash

set -e

norm=$(tput sgr0) || true
green=$(tput setaf 2) || true

docker-compose down

echo "${green}Cleaning completed.${norm}"
