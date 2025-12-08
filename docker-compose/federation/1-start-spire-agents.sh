#!/bin/bash

set -e

bb=$(tput bold)
nn=$(tput sgr0)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

docker compose -f "${DIR}"/docker-compose.yaml exec -T spire-server-broker bin/spire-server bundle show 

# Bootstrap trust to the SPIRE server for each agent by copying over the
# trust bundle into each agent container.
echo "${bb}Bootstrapping trust between SPIRE agents and SPIRE servers...${nn}"
docker compose -f "${DIR}"/docker-compose.yaml exec -T spire-server-broker bin/spire-server bundle show |
	docker compose -f "${DIR}"/docker-compose.yaml exec -T broker-webapp tee conf/agent/bootstrap.crt

docker compose -f "${DIR}"/docker-compose.yaml exec -T spire-server-stock bin/spire-server bundle show |
	docker compose -f "${DIR}"/docker-compose.yaml exec -T stock-quotes-service tee conf/agent/bootstrap.crt

# Start up the broker-webapp SPIRE agent.
echo "${bb}Starting broker-webapp SPIRE agent...${nn}"
docker compose -f "${DIR}"/docker-compose.yaml exec -d broker-webapp bin/spire-agent run

# Start up the stock-quotes-service SPIRE agent.
echo "${bb}Starting stock-quotes-service SPIRE agent...${nn}"
docker compose -f "${DIR}"/docker-compose.yaml exec -d stock-quotes-service bin/spire-agent run
