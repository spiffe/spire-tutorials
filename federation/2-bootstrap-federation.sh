#/bin/bash

set -e

bb=$(tput bold)
nn=$(tput sgr0)

echo "${bb}bootstrapping bundle from broker to quotes-service server...${nn}"
docker-compose exec -T spire-server-broker \
    /opt/spire/bin/spire-server bundle show -format spiffe > docker/spire-server-stockmarket.org/conf/broker.org.bundle
docker-compose exec -T spire-server-stock \
    /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://broker.org -path /opt/spire/conf/server/broker.org.bundle

echo "${bb}bootstrapping bundle from quotes-service to broker server...${nn}"
docker-compose exec -T spire-server-stock \
    /opt/spire/bin/spire-server bundle show -format spiffe > docker/spire-server-broker.org/conf/stockmarket.org.bundle
docker-compose exec -T spire-server-broker \
    /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://stockmarket.org -path /opt/spire/conf/server/stockmarket.org.bundle