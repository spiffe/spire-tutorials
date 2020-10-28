#/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

bb=$(tput bold) || true
nn=$(tput sgr0) || true
red=$(tput setaf 1) || true
green=$(tput setaf 2) || true

clean-env() {
    echo "${bb}Cleaning up...${nn}"
    bash "${DIR}"/scripts/clean-env.sh > /dev/null
}

trap clean-env EXIT

echo "${bb}Preparing environment...${nm}"
clean-env

# Creates Envoy JWT OPA scenario
bash "${DIR}"/scripts/set-env.sh

echo "${bb}Running test...${nm}"
# If balance is part of the response, then the request has a valid token and it was authorized by the OPA rules.
BALANCE_LINE="Your current balance is 10.95"
if curl -s $(minikube service frontend --url) | grep -qe "$BALANCE_LINE"; then
   echo "${green}Success${nn}"
   exit 0
fi

echo "${red}Failed! Request did not make it through the proxies.${nn}"
exit 1
