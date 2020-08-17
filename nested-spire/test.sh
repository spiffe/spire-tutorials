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
bash "${DIR}"/scripts/set-env.sh > /dev/null

log "Creating workload registration entries..."
bash "${DIR}"/scripts/create-workload-registration-entries.sh > /dev/null

log "checking nested JWT-SVID..."
# Fetch JWT-SVID and extract token
token=$(docker-compose exec -u 1001 -T nestedA-agent \
    /opt/spire/bin/spire-agent api fetch jwt -audience testIt -socketPath /opt/spire/sockets/workload_api.sock | sed -n '2p') || fail "JWT-SVID check failed"

# Validate token
validation_result=$(docker-compose exec -u 1001 -T nestedB-agent \
    /opt/spire/bin/spire-agent api validate jwt -audience testIt  -svid "${token}" -socketPath /opt/spire/sockets/workload_api.sock)

if echo $validation_result | grep -qe "SVID is valid."; then
   echo "${green}Success${nn}"
   exit 0
fi

echo "${red}Failed! JTW-SVID cannot be validated.${nn}".
exit 1
