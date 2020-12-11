#!/bin/bash

set -e

PARENT_DIR="$(dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )")"

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
      if docker-compose -f "${PARENT_DIR}"/docker-compose.yaml logs $1 | grep -qe "$2"; then
          log "${green}Entry is propagated.${nn}"
          return 0
      fi
      sleep 1
  done

  log "${red}timed out waiting for the entry to be progagated to the agent${red}"
  exit 1
}


# Workload for nestedA deployment
log "creating nestedA workload registration entry..."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml exec -T nestedA-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint "${PARENT_DIR}"/nestedA/agent/agent.crt.pem)" \
    -spiffeID "spiffe://example.org/nestedA/workload" \
    -selector "unix:uid:1001" \
    -ttl 0

check-entry-is-propagated nestedA-agent spiffe://example.org/nestedA/workload


# Workload for nestedB deployment
log "creating nestedB workload registration entry..."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml exec -T nestedB-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint "${PARENT_DIR}"/nestedB/agent/agent.crt.pem)" \
    -spiffeID "spiffe://example.org/nestedB/workload" \
    -selector "unix:uid:1001" \
    -ttl 0

check-entry-is-propagated nestedB-agent spiffe://example.org/nestedB/workload
