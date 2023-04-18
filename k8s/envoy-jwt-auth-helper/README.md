# Envoy JWT Auth Helper
Simple gRPC service that implements [Envoy's External Authorization Filter](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/ext_authz/v3/ext_authz.proto#envoy-v3-api-msg-extensions-filters-http-ext-authz-v3-extauthz).


_Envoy JWT Auth Helper_ needs to be configured as an External Authorization filter for Envoy. Then, for every HTTP request sent to the Envoy forward proxy, it obtains a JWT-SVID from the SPIRE Agent and inject it as a new request header. Finally the request is sent back to Envoy. 
On the other side, when the HTTP request arrives at the reverse proxy, the Envoy External Authorization module send the request to the _Envoy JWT Auth Helper_ which extracts the JWT-SVID from the header and connect to the SPIRE Agent to perform the validation. Once validated, the request is sent back to Envoy. If validation fails the request is denied.



## Modes
This simple authentication server supports 2 modes:

### jwt_injection

Connects to the SPIRE Agent to fetch a JWT-SVID which then is injected it into the request as a new header.

### jwt_svid_validator

Extracts the added header from the request and connects to the SPIRE Agent to validate it.

## Build

```console
go build
```

## Run:

```console
./envoy-jwt-auth-helper -config envoy-jwt-auth-helper.conf
```

## Configuration example:

```
socket_path = "unix:///tmp/agent.sock"
host = "127.0.0.1"
port = 9010
jwt_mode = "jwt_svid_validator"
audience = "spiffe://example.org/myservice"
```

## Build docker image:
```console
./build-images
```

To push the image to the scytale registry

```console
./build-images push
```

## As Envoy External Authorization filter

Include an External Authorization Filter in the Envoy configuration that connects to the service. This is accomplish by adding a new HTTP filter:

``` console
          http_filters:
          - name: envoy.ext_authz
            config:
              grpc_service:
                envoy_grpc:
                  cluster_name: ext-authz
                timeout: 0.5s
```

And the corresponding cluster:

``` console
  - name: ext-authz
    connect_timeout: 1s
    type: strict_dns
    http2_protocol_options: {}
    hosts:
      - socket_address:
          address: 127.0.0.1
          port_value: 9010
```

Note that the cluster is configured to talk to `127.0.0.1:9010`, the host and port set on the [configuration example](#configuration-example).
