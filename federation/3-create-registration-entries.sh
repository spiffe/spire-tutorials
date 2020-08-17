#/bin/bash

set -e

bb=$(tput bold)
nn=$(tput sgr0)

fingerprint() {
	# calculate the SHA1 digest of the DER bytes of the certificate using the
	# "coreutils" output format (`-r`) to provide uniform output from
	# `openssl sha1` on macOS and linux.
	cat $1 | openssl x509 -outform DER | openssl sha1 -r | awk '{print $1}'
}

BROKER_WEBAPP_AGENT_FINGERPRINT=$(fingerprint docker/broker-webapp/conf/agent.crt.pem)
QUOTES_SERVICE_AGENT_FINGERPRINT=$(fingerprint docker/stock-quotes-service/conf/agent.crt.pem)

echo "${bb}Creating registration entry for the broker-webapp...${nn}"
docker-compose exec spire-server-broker bin/spire-server entry create \
	-parentID spiffe://broker.org/spire/agent/x509pop/${BROKER_WEBAPP_AGENT_FINGERPRINT} \
	-spiffeID spiffe://broker.org/webapp \
	-selector unix:user:root \
	-federatesWith "spiffe://stockmarket.org"

echo "${bb}Creating registration entry for the stock-quotes-service...${nn}"
docker-compose exec spire-server-stock bin/spire-server entry create \
	-parentID spiffe://stockmarket.org/spire/agent/x509pop/${QUOTES_SERVICE_AGENT_FINGERPRINT} \
	-spiffeID spiffe://stockmarket.org/quotes-service \
	-selector unix:user:root \
	-federatesWith "spiffe://broker.org"