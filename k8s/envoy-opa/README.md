
# Using SPIFFE X.509 IDs with Envoy and Open Policy Agent Authorization

[Open Policy Agent](https://www.openpolicyagent.org/) (OPA) is an open source, general-purpose policy engine. The authorization provided by OPA (AuthZ) can be a good complement to the authentication that SPIRE offers (AuthN).

This tutorial adds [Open Policy Agent](https://www.openpolicyagent.org/) (OPA) to the [SPIRE Envoy-X.509 tutorial](../envoy-x509/README.md) to demonstrate how to combine SPIRE, Envoy, and OPA to perform X.509 SVID authentication and request authorization. The changes required to implement request authorization with OPA are shown here as a delta to that tutorial, so you should run, or at least read through, the SPIRE Envoy-X.509 tutorial first.


To illustrate it, let's extend the scenario created in the Envoy X.509 tutorial by adding an OPA Agent instance as a new sidecar for the backend service. Using Envoy’s External Authorization Filter feature in conjunction with OPA as an authorization service it is possible to enforce security policies for each request received by the Envoy instance in front of the backend service.

![SPIRE Envoy OPA integration diagram][diagram]

[diagram]: images/SPIRE_Envoy_OPA_X509_diagram.png "SPIRE Envoy OPA integration diagram"

As shown in the diagram, the frontend services connect to the backend service via an mTLS connection established by the Envoy instances which are authenticated using the SDS module provided by the SPIRE Agent. Envoy sends HTTP requests through the mTLS connections to the backend, where the HTTP requests are authorized or denied by the OPA Agent instance based on security policies.

In this tutorial you will learn how to:

* Add an OPA Agent to the existing backend service from the Envoy X.509 tutorial
* Add an External Authorization Filter to the Envoy configuration that connects Envoy to OPA
* Test successful OPA authorization using SPIRE with Envoy


# Prerequisites

Before proceeding, review the following:

* You'll need access to the Kubernetes environment configured when going through the [SPIRE Envoy-X.509 Tutorial](../envoy-x509/README.md). Optionally, you can create the Kubernetes environment with the `pre-set-env.sh` script described just below.
* Required YAML files for this tutorial can be found in the `k8s/envoy-opa` directory in https://github.com/spiffe/spire-tutorials. If you didn't already clone the spire-tutorials repository please do so now.

If the Kubernetes _Configure Envoy to Perform X.509 SVID Authentication_ tutorial environment is not available, you can use the following script to create it and use it as starting point for this tutorial. From the `k8s/envoy-opa` directory, run the following Bash script:

```console
$ bash scripts/pre-set-env.sh
```

The script will create all the resources needed for the SPIRE Server and SPIRE Agent to be available in the cluster and then will create all the resources for the SPIRE Envoy X.509 tutorial, which is the base scenario for this SPIRE Envoy and OPA Tutorial.

**Note:** The configuration changes needed to enable Envoy and OPA to work with SPIRE are shown as snippets in this tutorial. However, all of these settings have already been configured. You don't have to edit any configuration files.


# Part 1: Deploy Updated and New Resources

Assuming the SPIRE Envoy X.509 Tutorial as a starting point, there are some resources that need to be updated and others must be created.
The goal is to have the requests authorized by OPA before hitting the `backend` service. There is an mTLS connection already established between Envoy instances so the missing part is to add an OPA Agent to authorize requests based on policies.

## Update Backend Deployment

In order to let OPA authorize or reject requests coming to the `backend` service, it is necessary to add OPA as a sidecar to the deployment.
The new container is added and configured as follows in [`backend-deployment.yaml`](./k8s/backend/backend-deployment.yaml):

```console
- name: opa
  image: openpolicyagent/opa:0.50.2-envoy
  imagePullPolicy: IfNotPresent
  ports:
    - name: opa-envoy
      containerPort: 8182
      protocol: TCP
    - name: opa-api-port
      containerPort: 8181
      protocol: TCP
  args:
    - "run"
    - "--server"
    - "--config-file=/run/opa/opa-config.yaml"
    - "/run/opa/opa-policy.rego"
  volumeMounts:
    - name: backend-opa-policy
      mountPath: /run/opa
      readOnly: true
```
One thing to note is the use of the `openpolicyagent/opa:0.50.2-envoy` image. This image extends OPA with a gRPC server that implements the Envoy External Authorization API so OPA can communicate policy decisions with Envoy.

The ConfigMap `backend-opa-policy` needs to be added into the `volumes` section, like this:

```console
- name: backend-opa-policy
   configMap:
      name: backend-opa-policy-config
```

The ConfigMap `backend-opa-policy` provides two resources, `opa-config.yaml` described in [OPA Configuration](#opa-configuration) and the `opa-policy.rego` policy explained in the [Rego Policy](#opa-policy) section.

## OPA Configuration

For this tutorial we create the following OPA configuration file in [`opa-config.yaml`](./k8s/backend/config/opa-config.yaml):

```console
decision_logs:
   console: true
plugins:
   envoy_ext_authz_grpc:
      addr: :8182
      query: data.envoy.authz.allow
```

Here, `decision_logs.console: true` forces OPA to log the decisions locally at info level to the console. Later on in the tutorial we'll use these logs to examine the results for different requests.

Next, let's review the configuration for the `envoy_ext_authz_grpc` plugin. First, the `addr` key sets the listening address of the Envoy External Authorization gRPC server. This must match the value configured in the Envoy Filter resource detailed in a following section.
The `query` key defines the name of the policy to query. The next section focuses on details of the `envoy.authz.allow` policy specified for the `query` key.

## OPA Policy

OPA policies are expressed in a high-level declarative language called Rego. For this tutorial we created a sample rule named `allow` that includes three expressions (see [`opa-policy.rego`](./k8s/backend/config/opa-policy.rego)). All the expressions must evaluate to true for the rule to be true.

```console
default allow = false

allow {
   valid_path
   http_request.method == "GET"
   svc_spiffe_id == "spiffe://example.org/ns/default/sa/default/frontend"
}
```

Let's take a look at each expression individually. `valid_path` is a user-defined function created to ensure that only requests sent to permitted resources are allowed.

```console
import input.attributes.request.http as http_request

valid_path {
   glob.match("/balances/*", [], http_request.path)
}

valid_path {
   glob.match("/profiles/*", [], http_request.path)
}

valid_path {
   glob.match("/transactions/*", [], http_request.path)
}
```

The function `valid_path` makes use of the built-in function `glob.match(`_pattern_, _delimiters_, _match_`)` the output of which is true if _match_ can be found in _pattern_ which is separated by _delimiters_. Then, to express logical OR in Rego you define multiple rules with the same name. That is why there are three definitions of `valid_path`, one per valid resource.

The following expression defines that the HTTP method of the request must be equal to `GET`:

```console
http_request.method == "GET"
```

And the last expression corresponds also to a user-defined function:

```console
svc_spiffe_id == "spiffe://example.org/ns/default/sa/default/frontend"
```

The function `svc_spiffe_id` extracts the SPIFFE ID of the service from the `x-forwarded-client-cert` (XFCC) header in the request. The XFCC header is a proxy header which indicates certificate information for some or all of the clients or proxies that a request has passed through. The `svc_spiffe_id` function leverages two Envoy settings from `envoy.yaml` that modify the HTTP header:

```console
forward_client_cert_details: sanitize_set
set_current_client_cert_details:
   uri: true
```

When a client connection is mTLS, like this scenario, `forward_client_cert_details: sanitize_set` resets the XFCC header with the client certificate information and `set_current_client_cert_details` specifies the fields in the client certificate to be forwarded.

The XFCC header value is a comma (“,”) separated string. Each substring is an XFCC element and each XFCC element is a semicolon (“;”) separated string. Each substring is a key-value pair, grouped together by an equals (“=”) sign. The following keys are supported by Envoy:

   - `By`        The Subject Alternative Name (URI type) of the current proxy’s certificate.
   - `Hash`      The SHA 256 digest of the current client certificate.
   - `Cert`      The entire client certificate in URL encoded PEM format.
   - `Subject`   The Subject field of the current client certificate. The value is always double-quoted.
   - `URI`       The URI type Subject Alternative Name field of the current client certificate.
   - `DNS`       The DNS type Subject Alternative Name field of the current client certificate. A client certificate may contain multiple DNS type Subject Alternative Names, each will be a separate key-value pair.

The following is an XFCC header with a sample value that is split into two lines for readability:

```
x-forwarded-client-cert: By=spiffe://example.org/ns/default/sa/default/backend;Hash=a9317919875e178ce6d6
1eaa023490a2091299753ca5cd01d5323e40696d690b;URI=spiffe://example.org/ns/default/sa/default/frontend
```

In the `x-forwarded-client-cert` header, `Hash` is always set, and `By` is always set when the client certificate presents the URI type Subject Alternative Name value which is true when using X.509 SVIDs. Then `set_current_client_cert_details: uri: true` ensures that the URI type Subject Alternative Name (SAN) field is forwarded.

With these details about the XFCC header in mind and knowing that a X.509 SVID **must** contain exactly one URI SAN and that the SPIFFE ID is set as a URI type in the SAN extension, then it is possible to extract the SPIFFE ID from the XFCC header set by Envoy using the function:

```console
svc_spiffe_id = spiffe_id {
   [_, _, uri_type_san] := split(http_request.headers["x-forwarded-client-cert"], ";")
   [_, spiffe_id] := split(uri_type_san, "=")
}
```

Consequently, the policy will evaluate to true only when the request is sent to a valid resource (/balances/, /profiles/ or /transactions/) with a `GET` method and the request comes from a workload authenticated with the SPIFFE ID equal to `spiffe://example.org/ns/default/sa/default/frontend`. In all other cases, the request is not authorized by OPA and so is rejected by Envoy.

## Add an External Authorization Filter

Finally, this setup requires an External Authorization Filter that connects to the OPA instance. This new HTTP Filter is used with OPA as an authorization service to enforce security policies over API requests received by Envoy. This is accomplished by adding a new HTTP filter in `envoy.yaml`:

```console
- name: envoy.ext_authz
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.ext_authz.v3.ExtAuthz
    transport_api_version: V3
    with_request_body:
      max_request_bytes: 8192
      allow_partial_message: true
    failure_mode_allow: false
    grpc_service:
      google_grpc:
        target_uri: 127.0.0.1:8182
        stat_prefix: ext_authz
      timeout: 0.5s
```

Note that `target_uri` is configured to talk to the OPA service defined in a [previous step](#opa-configuration).
If you are curious, the complete configuration file is located at [k8s/backend/config/envoy.yaml](k8s/backend/config/envoy.yaml).

## Apply the New Resource

For the new configurations to take effect, the ConfigMap for the OPA configuration needs to be applied and the Envoy configuration needs to be updated. Ensure that the current working directory is `.../spire-tutorials/k8s/envoy-opa` and apply the new configurations using:

```console
$ kubectl apply -k k8s/.

configmap/backend-envoy configured
configmap/backend-opa-policy-config configured
deployment.apps/backend configured
```

Next, the `backend` pod needs to be restarted to pick up the new configurations:

```console
$ kubectl scale deployment backend --replicas=0
$ kubectl scale deployment backend --replicas=1
```


# Part 2: Test connections

Now that services are deployed and also registered in SPIRE, let's test the authorization that we've configured.

## Testing Valid Requests

The first test will demonstrate how a request that satisfies the policy allows for the display of associated data. To run this test, we need to find the IP address and port that make up the URL to use for accessing the data.

```console
$ kubectl get services

NAME            TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)          AGE
backend-envoy   ClusterIP      None          <none>           9001/TCP         6m53s
frontend        LoadBalancer   10.8.14.117   35.222.164.221   3000:32586/TCP   6m52s
frontend-2      LoadBalancer   10.8.7.57     35.222.190.182   3002:32056/TCP   6m53s
kubernetes      ClusterIP      10.8.0.1      <none>           443/TCP          59m
```

The `frontend` service will be available at the `EXTERNAL-IP` value and port `3000`, which was configured for our container. In the sample output shown above, the URL to navigate to is `http://35.222.164.221:3000`. Open your browser and navigate to the IP address shown for `frontend` in your environment, adding the port `:3000`. Once the page is loaded, you'll see the account details for user _Jacob Marley_.

![Frontend][frontend-view]

[frontend-view]: images/frontend_view.png "Frontend view"

Let's take a look at the OPA Agent logs to see what is happening behind the scenes. Use the following Bash script to get the logs for the OPA instance running next to the `backend` service and process the output with [`jq`](https://stedolan.github.io/jq/):

```console
$ bash scripts/backend-opa-logs.sh
```

The output shows the decision made for each request. For example, a request to the `frontend` service could produce a log entry similar to the following:

```
{
  "decision_id": "207b7b54-0ec0-4ffb-a531-c86a9f05c38d",
  "input": {
    "attributes": {
      ...
      "request": {
        "http": {
          "headers": {
            ":authority": "localhost:3003",
            ":method": "GET",
            ":path": "/profiles/2",
            "accept-encoding": "gzip",
            "content-length": "0",
            "user-agent": "Go-http-client/1.1",
            "x-forwarded-client-cert": "By=spiffe://example.org/ns/default/sa/default/backend;Hash=a9317919875e178ce6d61eaa023490a2091299753ca5cd01d5323e40696d690b;URI=spiffe://example.org/ns/default/sa/default/frontend",
            "x-forwarded-proto": "http",
            "x-request-id": "e0939bcf-8beb-4910-a980-be0468ec023f"
          },
          "method": "GET",
          "path": "/profiles/2",
          "protocol": "HTTP/1.1"
        },
      ...
      },
      ...
    },
   ...
  },

  "msg": "Decision Log",
  "query": "data.envoy.authz.allow",
  "requested_by": "",
  "result": true,
  "time": "2020-06-11T18:58:47Z",
  "timestamp": "2020-06-11T18:58:47.840319148Z",
  "type": "openpolicyagent.org/decision_logs"
}
```

The OPA `result` decision is true in this case, meaning the request is allowed to pass through the filter and reach the `backend` service because all of the following conditions defined in the `opa-policy.rego` Rego policy are met:
* The SPIFFE ID URI extracted from the `x-forwarded-client-cert` (XFCC) header matches the expected SPIFFE ID: `spiffe://example.org/ns/default/sa/default/frontend`
* The request's path matches: `/profiles/2`
* The HTTP method matches: `GET`

## Testing Invalid Requests

On the other hand, following the same steps we can confirm that a request that does not satisfy the policy prevents the associated data from being displayed. In this case the `frontend-2` service is not able to talk to the `backend` service because its SPIFFE ID does not satisfy the policy for the OPA Agent.
As a result, when you connect to the URL for the `frontend-2` service (e.g. `http://35.222.190.182:3002`), the browser only displays the title without any account details.

![Frontend-2-no-details][frontend-2-view-no-details]

[frontend-2-view-no-details]: images/frontend-2_view_no_details.png "Frontend-2 view no details account"

After trying to display the `frontend-2` data, you can verify the decision made by OPA using the same `scripts/backend-opa-logs.sh` script as performed in the previous section. A similar log entry is available for the `frontend-2` service but with the result equal to `false` due to the SPIFFE ID mismatch.

## Retesting frontend-2 with a New Policy

Let's update the Rego policy to match the SPIFFE ID of the `frontend-2` and test again. There is a Bash script that we can leverage to complete this task. Once executed, it will open the editor defined by your `KUBE_EDITOR`, or `EDITOR` environment variables, or fall back to `vi` for Linux or Notepad for Windows.

```console
$ bash scripts/backend-update-policy.sh
```

With the editor open, look for the following line that specifies the SPIFFE ID:

```console
svc_spiffe_id == "spiffe://example.org/ns/default/sa/default/frontend"
```

Update that line to match the SPIFFE ID for the `frontend-2` workload:

```console
svc_spiffe_id == "spiffe://example.org/ns/default/sa/default/frontend-2"
```

Save the changes and exit. The `backend-update-policy.sh` script resumes. The script applies the new version of the ConfigMap and then restarts the `backend` pod to pick up the new rule.
Wait some seconds for the deployment to propagate before trying to view the `frontend-2` service in your browser again.
Once the pod is ready, refresh the browser using the correct URL for the `frontend-2` service (e.g. `http://35.222.190.182:3002`). As a result, now the page shows the account details for user _Alex Fergus_.

![Frontend-2][frontend-2-view]

[frontend-2-view]: images/frontend-2_view.png "Frontend-2 view"

On the other hand, if you now connect to the URL for the `frontend` service (e.g. `http://35.222.164.221:3000`), the browser only displays the title without any account details. This is the expected behaviour as the policy was updated and now the SPIFFE ID of the `frontend` service does not satisfy the policy anymore.

# Cleanup

When you are finished, you can use the following commands to clean the environment created for the tutorial. It will remove:
   * All resources created for this SPIRE - Envoy with OPA integration tutorial
   * All resources created for the SPIRE - Envoy X.509 integration tutorial
   * All deployments and configurations for the SPIRE Agent, SPIRE Server, and namespace

```console
$ bash scripts/clean-env.sh
```
