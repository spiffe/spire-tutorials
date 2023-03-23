FROM ghcr.io/spiffe/spire-agent:1.5.1

COPY conf/agent.conf /opt/spire/conf/agent/agent.conf
COPY conf/agent.key.pem /opt/spire/conf/agent/agent.key.pem
COPY conf/agent.crt.pem /opt/spire/conf/agent/agent.crt.pem
COPY broker-webapp /usr/local/bin/broker-webapp

# Copy convenient tools to be used in the tutorial
COPY --link --from=alpine:3.17 /bin/cat /bin/cat
COPY --link --from=alpine:3.17 /bin/sh /bin/sh
COPY --link --from=alpine:3.17 /usr/bin/tee /usr/bin/tee
COPY --link --from=alpine:3.17 /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1

WORKDIR /opt/spire
ENTRYPOINT []

CMD broker-webapp
