  
#!/bin/bash

set -e

bb=$(tput bold)
nn=$(tput sgr0)

# Bootstrap trust to the SPIRE server for each agent by copying over the
# trust bundle into each agent container.
echo "${bb}Bootstrapping trust between SPIRE agents and SPIRE servers...${nn}"
docker-compose exec -T spire-server-broker bin/spire-server bundle show |
	docker-compose exec -T broker-webapp tee conf/agent/bootstrap.crt > /dev/null
docker-compose exec -T spire-server-stocks bin/spire-server bundle show |
	docker-compose exec -T stock-quotes-service tee conf/agent/bootstrap.crt > /dev/null

# Start up the broker-webapp SPIRE agent.
echo "${bb}Starting broker-webapp SPIRE agent...${nn}"
docker-compose exec -d broker-webapp bin/spire-agent run

# Start up the stock-quotes-service SPIRE agent.
echo "${bb}Starting stock-quotes-service SPIRE agent...${nn}"
docker-compose exec -d stock-quotes-service bin/spire-agent run