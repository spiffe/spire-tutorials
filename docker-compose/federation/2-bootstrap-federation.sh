#/bin/bash

set -e

bb=$(tput bold)
nn=$(tput sgr0)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "${bb}bootstrapping bundle from broker to quotes-service server...${nn}"
docker-compose -f "${DIR}"/docker-compose.yaml exec -T spire-server-broker \
    /opt/spire/bin/spire-server bundle show -format spiffe > "${DIR}"/docker/spire-server-stockmarket.example/conf/broker.example.bundle
docker-compose -f "${DIR}"/docker-compose.yaml exec -T spire-server-stock \
    /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://broker.example -path /opt/spire/conf/server/broker.example.bundle

echo "${bb}bootstrapping bundle from quotes-service to broker server...${nn}"
docker-compose -f "${DIR}"/docker-compose.yaml exec -T spire-server-stock \
    /opt/spire/bin/spire-server bundle show -format spiffe > "${DIR}"/docker/spire-server-broker.example/conf/stockmarket.example.bundle
docker-compose -f "${DIR}"/docker-compose.yaml exec -T spire-server-broker \
    /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://stockmarket.example -path /opt/spire/conf/server/stockmarket.example.bundle
