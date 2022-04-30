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
      if docker-compose -f "${PARENT_DIR}"/docker-compose.yaml logs $1 | grep -qe "$2"; then
          log "${green}Entry is propagated.${nn}"
          return 0
      fi
      sleep 1
  done

  log "${red}timed out waiting for the entry to be progagated to the agent${norm}"
  exit 1
}


# Configure the environment-dependent CGROUP matchers for the docker workload
# attestors.
CGROUP_MATCHERS="TEreso"
if [ -n "${GITHUB_WORKFLOW}" ]; then
    CGROUP_MATCHERS='"/actions_job/<id>"'
fi
sed -i.bak "s#\#container_id_cgroup_matchers#container_id_cgroup_matchers#" "${PARENT_DIR}"/root/agent/agent.conf
sed -i.bak "s#CGROUP_MATCHERS#$CGROUP_MATCHERS#" "${PARENT_DIR}"/root/agent/agent.conf

# create a shared folder for root agent socket to be accessed by nestedA and nestedB servers
mkdir -p "${PARENT_DIR}"/sharedRootSocket


# Starts root SPIRE deployment
log "Generate certificates for the root SPIRE deployment"
setup "${PARENT_DIR}"/root/server "${PARENT_DIR}"/root/agent

log "Start root server"
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d root-server

log "bootstrapping root-agent."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml exec -T root-server /opt/spire/bin/spire-server bundle show > "${PARENT_DIR}"/root/agent/bootstrap.crt

log "Start root agent"
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d root-agent

# Creates registration entries for the nested servers
log "creating nestedA downstream registration entry..."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml exec -T root-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint "${PARENT_DIR}"/root/agent/agent.crt.pem)" \
    -spiffeID "spiffe://example.org/nestedA" \
    -selector "docker:label:org.example.name:nestedA-server" \
    -downstream \
    -ttl 3600

check-entry-is-propagated root-agent spiffe://example.org/nestedA

log "creating nestedB downstream registration entry..."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml exec -T root-server \
    /opt/spire/bin/spire-server entry create \
    -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint "${PARENT_DIR}"/root/agent/agent.crt.pem)" \
    -spiffeID "spiffe://example.org/nestedB" \
    -selector "docker:label:org.example.name:nestedB-server" \
    -downstream \
    -ttl 3600

check-entry-is-propagated root-agent spiffe://example.org/nestedB


# Starts nestedA SPIRE deployment
log "Generate certificates for the nestedA deployment"
setup "${PARENT_DIR}"/nestedA/server "${PARENT_DIR}"/nestedA/agent

log "Starting nestedA-server.."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d nestedA-server

log "bootstrapping nestedA agent..."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml exec -T nestedA-server /opt/spire/bin/spire-server bundle show > "${PARENT_DIR}"/nestedA/agent/bootstrap.crt

log "Starting nestedA-agent..."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d nestedA-agent


# Starts nestedB SPIRE deployment
log "Generate certificates for the nestedB deployment"
setup "${PARENT_DIR}"/nestedB/server "${PARENT_DIR}"/nestedB/agent

log "Starting nestedB-server.."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d nestedB-server

log "bootstrapping nestedB agent..."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml exec -T nestedB-server /opt/spire/bin/spire-server bundle show > "${PARENT_DIR}"/nestedB/agent/bootstrap.crt

log "Starting nestedB-agent..."
docker-compose -f "${PARENT_DIR}"/docker-compose.yaml up -d nestedB-agent
