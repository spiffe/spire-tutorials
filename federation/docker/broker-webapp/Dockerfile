FROM gcr.io/spiffe-io/spire-agent:unstable

COPY conf/agent.conf /opt/spire/conf/agent/agent.conf
COPY conf/agent.key.pem /opt/spire/conf/agent/agent.key.pem
COPY conf/agent.crt.pem /opt/spire/conf/agent/agent.crt.pem
COPY broker-webapp /usr/local/bin/broker-webapp

WORKDIR /opt/spire
ENTRYPOINT []

CMD broker-webapp