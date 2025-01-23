#!/bin/bash

norm=$(tput sgr0) || true
green=$(tput setaf 2) || true
red=$(tput setaf 1) || true
bold=$(tput bold) || true

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


log() {
  echo "${bold}$*${norm}"
}

clean-env() {
  log "Cleaning up..."
  bash "${DIR}"/scripts/clean-env.sh
}

trap clean-env EXIT


log "Preparing environment..."
clean-env
bash "${DIR}"/scripts/set-env.sh
bash "${DIR}"/scripts/create-workload-registration-entry.sh

log "Checking Statsd received metrics pushed by SPIRE..."

STATSD_LOG_LINE="MetricLineReceiver connection with .* established"
for ((i=0;i<60;i++)); do
    if ! docker compose -f "${DIR}"/docker-compose.yaml logs --tail=10 -t graphite-statsd | grep -qe "${STATSD_LOG_LINE}" ; then
	sleep 1
	continue
    fi
    METRIC_RECEIVED=1
    break
done
if [ -z "${METRIC_RECEIVED}" ]; then
    echo "${red}Failed!. Timed out waiting for SPIRE to push metrics to Statsd.${nn}"
    exit 1
fi

log "Checking that Prometheus can reach the endpoint exposed by SPIRE..."
for ((i=0;i<60;i++)); do
    if ! docker compose -f "${DIR}"/docker-compose.yaml exec -T prometheus wget -S spire-server:8088/ 2>&1 | grep -qe "200 OK" ; then
	sleep 1
	continue
    fi
    CONNECTION_OK=1
    break
done
if [ -z "${CONNECTION_OK}" ]; then
    echo "${red}Failed!. Timed out waiting for Prometheus to successfully fetch metrics from SPIRE.${nn}"
    exit 1
fi

echo "${green}Success${norm}"
exit 0
