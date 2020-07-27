#/bin/bash

set -e

bb=$(tput bold)
nn=$(tput sgr0)

echo "${bb}bootstrapping bundle from broker to quotes-service server...${nn}"
docker-compose exec -T spire-server-broker \
    /opt/spire/bin/spire-server experimental bundle show > docker/spire-server-stocksmarket.org/conf/broker.org.bundle
docker-compose exec -T spire-server-stocks \
    /opt/spire/bin/spire-server experimental bundle set -id spiffe://broker.org -path /opt/spire/conf/server/broker.org.bundle

echo "${bb}bootstrapping bundle from quotes-service to broker server...${nn}"
docker-compose exec -T spire-server-stocks \
    /opt/spire/bin/spire-server experimental bundle show > docker/spire-server-broker.org/conf/stocksmarket.org.bundle
docker-compose exec -T spire-server-broker \
    /opt/spire/bin/spire-server experimental bundle set -id spiffe://stocksmarket.org -path /opt/spire/conf/server/stocksmarket.org.bundle