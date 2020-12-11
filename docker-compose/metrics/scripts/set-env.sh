#!/bin/bash

set -e

norm=$(tput sgr0) || true
bold=$(tput bold) || true


log() {
    echo "${bold}$*${norm}"
}

log "Start StatsD-Graphite server"
docker-compose up -d graphite-statsd

log "Start prometheus server"
docker-compose up -d prometheus

log "Start SPIRE Server"
docker-compose up -d spire-server

log "bootstrapping SPIRE Agent..."
docker-compose exec -T spire-server /opt/spire/bin/spire-server bundle show > spire/agent/bootstrap.crt

log "Start SPIRE Agent"
docker-compose up -d spire-agent
