FROM ghcr.io/spiffe/spire-server:1.11.2

# Override spire configurations
COPY conf/server.conf /opt/spire/conf/server/server.conf
COPY conf/agent-cacert.pem /opt/spire/conf/server/agent-cacert.pem

# Copy convenient tools to be used in the tutorial
COPY --link --from=alpine:3.17 /bin/cat /bin/cat
COPY --link --from=alpine:3.17 /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1

WORKDIR /opt/spire
