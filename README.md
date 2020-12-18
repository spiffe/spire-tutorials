# SPIRE Tutorials

The tutorials in this repo describe how to install SPIRE and integrate it with software typically used with SPIRE. The following tutorials are available:

| Tutorial | Platform |
| --- | --- |
| [Quickstart for Kubernetes](https://spiffe.io/spire/try/getting-started-k8s/) | Kubernetes |
| [AWS OIDC Authentication](https://spiffe.io/spire/try/oidc-federation-aws/) | Kubernetes |
| [Vault OIDC Authentication](k8s/oidc-vault) | Kubernetes |
| [Integrating with Envoy using X.509 certs](k8s/envoy-x509) | Kubernetes |
| [Integrating with Envoy using JWT](k8s/envoy-jwt) | Kubernetes |
| [Using SPIFFE X.509 IDs with Envoy and Open Policy Agent Authorization](k8s/envoy-opa) | Kubernetes |
| [Using SPIFFE JWT IDs with Envoy and Open Policy Agent Authorization](k8s/envoy-jwt-opa) | Kubernetes |
| [Nested SPIRE](docker-compose/nested-spire) | Docker Compose |
| [Federation](docker-compose/federation) | Docker Compose |
| [Configure SPIRE to Emit Telemetry](docker-compose/metrics) | Docker Compose |

Additional examples of how to install and deploy SPIRE are available. The spiffe.io [Try SPIRE](https://spiffe.io/spire/try/) page includes a [Quickstart for Linux and MacOS X](https://spiffe.io/spire/try/getting-started-linux-macos-x/) and [SPIFFE Library Usage Examples](https://spiffe.io/spire/try/spiffe-library-usage-examples/). The [SPIRE Examples](https://github.com/spiffe/spire-examples) repo on GitHub includes more usage examples for Kubernetes deployments, including Postgres integration, and a Docker-based Envoy example.

For general information about SPIRE and the [SPIFFE](https://github.com/spiffe/spiffe) zero-trust authentication spec that SPIRE implements, see the SPIRE [GitHub repo](https://github.com/spiffe/spire) and [spiffe.io website](https://spiffe.io).
