#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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

setup() {
    # Generates certs
    go run "${DIR}/gencerts.go" "$@"
}

fingerprint() {
	# calculate the SHA1 digest of the DER bytes of the certificate using the
	# "coreutils" output format (`-r`) to provide uniform output from
	# `openssl sha1` on macOS and linux.
	openssl x509 -in "$1" -outform DER | openssl sha1 -r | awk '{print $1}'
}

check-entry-is-propagated() {
  # Check at most 30 times that the agent has successfully synced down the workload entry.
  # Wait one second between checks.
  log "Checking registration entry is propagated..."
  for ((i=1;i<=30;i++)); do
      if docker-compose logs $1 | grep -qe "$2"; then
          log "${green}Entry is propagated.${nn}"
          return 0
      fi
      sleep 1
  done

  log "${red}timed out waiting for the entry to be progagated to the agent${norm}"
  exit 1
}


# create a shared folder for root agent socket to be accessed by nestedA and nestedB servers
mkdir -p sharedRootSocket


# Starts root SPIRE deployment
log "Generate certificates for the root SPIRE deployment"
setup root/server root/agent

log "Start root server"
docker-compose up -d root-server

log "bootstrapping root-agent."
docker-compose exec -T root-server /opt/spire/bin/spire-server bundle show > root/agent/bootstrap.crt

log "Start root agent"
docker-compose up -d root-agent

# Creates registration entries for the nested servers
log "creating nestedA downstream registration entry..."
docker-compose exec -T root-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint root/agent/agent.crt.pem)" \
    -spiffeID "spiffe://example.org/nestedA" \
    -selector "docker:label:org.example.name:nestedA-server" \
    -downstream \
    -ttl 3600

check-entry-is-propagated root-agent spiffe://example.org/nestedA

log "creating nestedB downstream registration entry..."
docker-compose exec -T root-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint root/agent/agent.crt.pem)" \
    -spiffeID "spiffe://example.org/nestedB" \
    -selector "docker:label:org.example.name:nestedB-server" \
    -downstream \
    -ttl 3600

check-entry-is-propagated root-agent spiffe://example.org/nestedB


# Starts nestedA SPIRE deployment
log "Generate certificates for the nestedA deployment"
setup nestedA/server nestedA/agent

log "Starting nestedA-server.."
docker-compose up -d nestedA-server

log "bootstrapping nestedA agent..."
docker-compose exec -T nestedA-server /opt/spire/bin/spire-server bundle show > nestedA/agent/bootstrap.crt

log "Starting nestedA-agent..."
docker-compose up -d nestedA-agent


# Starts nestedB SPIRE deployment
log "Generate certificates for the nestedB deployment"
setup nestedB/server nestedB/agent

log "Starting nestedB-server.."
docker-compose up -d nestedB-server

log "bootstrapping nestedB agent..."
docker-compose exec -T nestedB-server /opt/spire/bin/spire-server bundle show > nestedB/agent/bootstrap.crt

log "Starting nestedB-agent..."
docker-compose up -d nestedB-agent
