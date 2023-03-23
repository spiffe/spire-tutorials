#/bin/bash

set -e

bb=$(tput bold)
nn=$(tput sgr0)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

fingerprint() {
	# calculate the SHA1 digest of the DER bytes of the certificate using the
	# "coreutils" output format (`-r`) to provide uniform output from
	# `openssl sha1` on macOS and linux.
	cat $1 | openssl x509 -outform DER | openssl sha1 -r | awk '{print $1}'
}

BROKER_WEBAPP_AGENT_FINGERPRINT=$(fingerprint ${DIR}/docker/broker-webapp/conf/agent.crt.pem)
QUOTES_SERVICE_AGENT_FINGERPRINT=$(fingerprint ${DIR}/docker/stock-quotes-service/conf/agent.crt.pem)

echo "${bb}Creating registration entry for the broker-webapp...${nn}"
docker-compose -f "${DIR}"/docker-compose.yaml exec -T spire-server-broker bin/spire-server entry create \
	-parentID spiffe://broker.example/spire/agent/x509pop/${BROKER_WEBAPP_AGENT_FINGERPRINT} \
	-spiffeID spiffe://broker.example/webapp \
	-selector unix:uid:0 \
	-federatesWith "spiffe://stockmarket.example"

echo "${bb}Creating registration entry for the stock-quotes-service...${nn}"
docker-compose -f "${DIR}"/docker-compose.yaml exec -T spire-server-stock bin/spire-server entry create \
	-parentID spiffe://stockmarket.example/spire/agent/x509pop/${QUOTES_SERVICE_AGENT_FINGERPRINT} \
	-spiffeID spiffe://stockmarket.example/quotes-service \
	-selector unix:uid:0 \
	-federatesWith "spiffe://broker.example"
