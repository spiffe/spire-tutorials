# SPIRE Tutorials

The tutorials in this repo describe how to install SPIRE and integrate it with software typically used with SPIRE. All of the current tutorials work only on Kubernetes. The following tutorials are available:

* [SPIRE quickstart](https://spiffe.io/spire/try/getting-started-k8s/)
* [Authenticating to AWS using OIDC ](https://spiffe.io/spire/try/oidc-federation-aws/)
* [Integrating with Envoy using X.509 certs](k8s/envoy-x509)
* [Integrating with Envoy using JWT](k8s/envoy-jwt)

Additional examples of how to install and deploy SPIRE are available. The [SPIRE](https://spiffe.io/spire/try/) website includes a [Linux/Mac quickstart guide](https://spiffe.io/spire/try/getting-started-linux-macos-x/) and [SPIFFE library](https://spiffe.io/spire/try/spiffe-library-usage-examples/) usage examples. The [SPIRE examples](../spire-examples) repo on GitHub includes more usage examples for Kubernetes deployments, Postgres integration, and a Docker-based Envoy example.

For general information about SPIRE and the [SPIFFE](../spiffe) zero-trust authentication spec that SPIRE implements, see the SPIRE [GitHub repo](../spire) and [website](https://spiffe.io).
