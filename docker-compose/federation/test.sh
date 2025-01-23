#!/bin/bash

norm=$(tput sgr0) || true
green=$(tput setaf 2) || true
red=$(tput setaf 1) || true
bold=$(tput bold) || true

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

timestamp() {
    date -u "+[%Y-%m-%dT%H:%M:%SZ]"
}

log() {
    echo "${bold}$(timestamp) $*${norm}"
}

fail() {
    echo "${red}$(timestamp) $*${norm}"
    exit 1
}

clean-env() {
    log "Cleaning up..."
    bash "${DIR}"/scripts/clean-env.sh
}

trap clean-env EXIT


log "Preparing Nested SPIRE environment..."
clean-env

bash "${DIR}"/scripts/set-env.sh

for ((i=0;i<60;i++)); do
    if docker compose -f "${DIR}"/docker-compose.yaml exec -T broker-webapp wget localhost:8080/quotes -O - 2>&1 | grep -qe "Quotes service unavailable"; then
	log "Service not found, retrying..."
	sleep 1
	continue
    fi
    CONNECTION_OK=1
    break
done

if [ "${CONNECTION_OK}" ]; then
    echo "${green}Success${norm}"
    exit 0
fi

fail "Failed!. Timed out waiting quote service communicate with webapp from SPIRE."
exit 1
