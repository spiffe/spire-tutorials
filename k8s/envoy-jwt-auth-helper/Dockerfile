FROM golang:latest AS build-stage

WORKDIR /app
COPY . .
RUN go mod download
RUN go build

FROM debian:buster-slim AS production-stage
RUN apt update && DEBIAN_FRONTEND=noninteractive apt full-upgrade -y && \
apt install -y dumb-init iputils-ping curl procps

RUN mkdir /opt/helper
COPY --from=build-stage /app/envoy-jwt-auth-helper /opt/helper
ENTRYPOINT ["/usr/bin/dumb-init", "/opt/helper/envoy-jwt-auth-helper"]
CMD []
