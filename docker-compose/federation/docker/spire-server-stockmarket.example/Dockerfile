FROM gcr.io/spiffe-io/spire-server:0.11.0

# Override spire configurations
COPY conf/server.conf /opt/spire/conf/server/server.conf
COPY conf/agent-cacert.pem /opt/spire/conf/server/agent-cacert.pem

WORKDIR /opt/spire
