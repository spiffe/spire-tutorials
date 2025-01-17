#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$(dirname "$DIR")"

norm=$(tput sgr0) || true
green=$(tput setaf 2) || true
red=$(tput setaf 1) || true
bold=$(tput bold) || true


timestamp() {
    date -u "+[%Y-%m-%dT%H:%M:%SZ]"
}

log() {
    echo "${bold}$(timestamp) $*${norm}"
}

check-entry-is-propagated() {
  # Check at most 30 times that the agent has successfully synced down the workload entry.
  # Wait one second between checks.
  log "Checking registration entry is propagated..."
  for ((i=1;i<=30;i++)); do
      if docker compose -f "${PARENT_DIR}"/docker-compose.yaml exec -T $1 cat /opt/spire/agent.log 2>&1 | grep -qe "$2"; then
          log "${green}Entry is propagated.${nn}"
          return 0
      fi
      sleep 1
  done

  log "${red}timed out waiting for the entry to be progagated to the agent${norm}"
  exit 1
}


log "Building"
bash "${PARENT_DIR}"/build.sh

log "Starting container"
docker compose -f "${PARENT_DIR}"/docker-compose.yaml up -d

bash "${PARENT_DIR}"/1-start-spire-agents.sh

bash "${PARENT_DIR}"/2-bootstrap-federation.sh

bash "${PARENT_DIR}"/3-create-registration-entries.sh

check-entry-is-propagated stock-quotes-service spiffe://stockmarket.example/quotes-service
check-entry-is-propagated broker-webapp spiffe://broker.example/webapp
