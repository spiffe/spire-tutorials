#!/bin/bash

set -e

PARENT_DIR="$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")"

norm=$(tput sgr0) || true
bold=$(tput bold) || true

log() {
    echo "${bold}$*${norm}"
}

log "Start StatsD-Graphite server"
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d graphite-statsd

log "Start prometheus server"
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d prometheus

log "Start SPIRE Server"
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d spire-server

log "bootstrapping SPIRE Agent..."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml exec -T spire-server /opt/spire/bin/spire-server bundle show > "${PARENT_DIR}"/spire/agent/bootstrap.crt

log "Start SPIRE Agent"
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d spire-agent
