FROM gcr.io/spiffe-io/spire-agent:unstable as spire

COPY conf/agent.conf /opt/spire/conf/agent/agent.conf
COPY conf/agent.key.pem /opt/spire/conf/agent/agent.key.pem
COPY conf/agent.crt.pem /opt/spire/conf/agent/agent.crt.pem
COPY stock-quotes-service /usr/local/bin/stock-quotes-service

WORKDIR /opt/spire
ENTRYPOINT []
CMD stock-quotes-service
