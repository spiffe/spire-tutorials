
# Configure Envoy to Perform X.509 SVID Authentication

This tutorial builds on the [Kubernetes Quickstart Tutorial](../quickstart/) to demonstrate how to configure SPIRE to provide service identity dynamically in the form of X.509 certificates that will be consumed by Envoy secret discovery service (SDS). The changes required to implement X.509 SVID authentication are shown here as a delta to that tutorial, so you should run, or at least read through, the Kubernetes Quickstart Tutorial first.

To illustrate X.509 authentication, we create a simple scenario with three services. One service will be the backend that is a simple nginx instance serving static data. On the other side, we run two instances of the `Symbank` demo banking application acting as the frontend services. The `Symbank` frontend services send HTTP requests to the nginx backend to get the user account details.

![SPIRE Envoy integration diagram][diagram]

[diagram]: images/SPIRE_Envoy_diagram.png "SPIRE Envoy integration diagram"

As shown in the diagram, the frontend services connect to the backend service via an mTLS connection established by the Envoy instances that perform X.509 SVID authentication on each workload's behalf.

In this tutorial you will learn how to:

* Set up SDS support in SPIRE
* Configure Envoy SDS to consume X.509 certificates provided by SPIRE
* Create registration entries on the SPIRE Server for the Envoy instances
* Test successful X.509 authentication using SPIRE
* Optionally, configure an Envoy RBAC HTTP filter policy


# Prerequisites

Before proceeding, review the following:

* You'll need access to the Kubernetes environment configured when going through the [Kubernetes Quickstart Tutorial](../quickstart/). Optionally, you can create the Kubernetes environment with the `pre-set-env.sh` script described just below. The Kubernetes environment must be able to expose an Ingress to the public internet. _Note: This is generally not true for local Kubernetes environments such as Minikube._
* Required YAML files for this tutorial can be found in the `k8s/envoy-x509` directory in https://github.com/spiffe/spire-tutorials. If you didn't already clone the repo for the _Kubernetes Quickstart Tutorial_ please do so now.

If the _Kubernetes Quickstart Tutorial_ environment is not available, you can use the following script to create it and use it as starting point for this tutorial. From the `k8s/envoy-x509` directory, run the following command:

```console
$ bash scripts/pre-set-env.sh
```

The script will create all the resources needed for the SPIRE Server and SPIRE Agent to be available in the cluster.


# Part 1: Update SPIRE Agent to Support SDS

As we want Envoy to consume certificates via SDS, we need to configure SPIRE to provide them by enabling SDS support on the SPIRE Agent. The `spire-agent-configmap.yaml` file in the `k8s/envoy-x509` directory includes the following line to enable SDS support:

```console
enable_sds: true
```

From the `k8s/envoy-x509` directory apply the new configmap for the SPIRE Agent:

```console
$ kubectl apply -f spire-agent-configmap.yaml
```

Delete the SPIRE Agent pod so it is restarted using the new configuration provided in the previous step.

```console
$ kubectl -n spire delete pod $(kubectl -n spire get pods --selector=app=spire-agent --output=jsonpath="{..metadata.name}")
```

Use the following command to check the `spire-agent` status. When the pod displayed as _Running_, continue to part 2.

```console
$ kubectl -n spire get pod --selector=app=spire-agent
```


# Part 2: Run Workloads

Now let's deploy the workloads we'll use in this tutorial. It consists of three workloads: as mentioned before, two instances of the `Symbank` demo application will act as frontend services and the other, an instance of _nginx_ serving static files, will be the backend service.

To make a distinction between the two instances of the `Symbank` application, let's call one `frontend` and the other `frontend-2`. The former is configured to present data related to the user _Jacob Marley_ and the second will show account details for the user _Alex Fergus_.

## Deploy all Workloads

Ensure that the current working directory is `.../spire-tutorials/k8s/envoy-x509` and deploy the new resources using:

```console
$ kubectl apply -k k8s/.

configmap/backend-balance-json-data created
configmap/backend-envoy created
configmap/backend-profile-json-data created
configmap/backend-transactions-json-data created
configmap/frontend-2-envoy created
configmap/frontend-envoy created
configmap/symbank-webapp-2-config created
configmap/symbank-webapp-config created
service/backend-envoy created
service/frontend-2 created
service/frontend created
deployment.apps/backend created
deployment.apps/frontend-2 created
deployment.apps/frontend created
```

The `kubectl apply` command creates the following resources:
   * A Deployment for each of the workloads. It contains one container for our service plus the Envoy sidecar.
   * A Service for each workload. It is used to communicate between them.
   * Several Configmaps:
      * _*-json-data_ are used to provide static files to the nginx instance running as the backend service.
      * _*-envoy_ contains the Envoy configuration for each workload.
      * _symbank-webapp-*_ contains the configuration supplied to each instance of the frontend services.

The next two sections focus on the settings needed to configure Envoy. 

### SPIRE Agent Cluster

For Envoy SDS to consume X.509 certificates provided by SPIRE Agent, we configure a cluster that points to the Unix Domain Socket the SPIRE Agent provides. The Envoy configuration for the backend service is located at `k8s/backend/config/envoy.yaml`.

```console
clusters:
- name: spire_agent
  connect_timeout: 0.25s
  http2_protocol_options: {}
  hosts:
    - pipe:
        path: /run/spire/sockets/agent.sock
```

### TLS Certificates

To obtain a TLS certificate and private key from SPIRE, you set up an SDS configuration within a TLS context. The name of the TLS certificate is the SPIFFE ID of the service that Envoy is acting as a proxy for. 
Furthermore SPIRE provides a validation context per trust domain that Envoy uses to verify peer certificates.

```console
tls_context:
   common_tls_context:
      tls_certificate_sds_secret_configs:
      - name: "spiffe://example.org/ns/default/sa/default/backend"
      sds_config:
         api_config_source:
            api_type: GRPC
            grpc_services:
            envoy_grpc:
               cluster_name: spire_agent
      combined_validation_context:
      # validate the SPIFFE ID of incoming clients (optionally)
      default_validation_context:
         match_subject_alt_names:
            - "spiffe://example.org/ns/default/sa/default/frontend"
            - "spiffe://example.org/ns/default/sa/default/frontend-2"
      # obtain the trust bundle from SDS
      validation_context_sds_secret_config:
         name: "spiffe://example.org"
         sds_config:
            api_config_source:
            api_type: GRPC
            grpc_services:
               envoy_grpc:
                 cluster_name: spire_agent
```

Similar configurations are set on both frontend services to establish an mTLS communication. Check the configuration of the cluster named `backend` in `k8s/frontend/config/envoy.yaml` and `k8s/frontend-2/config/envoy.yaml`.

## Create Registration Entries

In order to get X.509 certificates issued by SPIRE, the services must be registered. We achieve this by creating registration entries on the SPIRE Server for each of our workloads. Let's use the following Bash script:

```console
$ bash create-registration-entries.sh
```

Once the script is run, the list of created registration entries will be shown. The output will show other registration entries created by the [Kubernetes Quickstart Tutorial](../quickstart/). The important ones here are the three new entries belonging to each of our workloads:

```console
...
Entry ID      : 0d02d63f-712e-47ad-a06e-853c8b062835
SPIFFE ID     : spiffe://example.org/ns/default/sa/default/backend
Parent ID     : spiffe://example.org/ns/spire/sa/spire-agent
TTL           : 3600
Selector      : k8s:container-name:envoy
Selector      : k8s:ns:default
Selector      : k8s:pod-label:app:backend
Selector      : k8s:sa:default

Entry ID      : 3858ec9b-f924-4f69-b812-5134aa33eaee
SPIFFE ID     : spiffe://example.org/ns/default/sa/default/frontend
Parent ID     : spiffe://example.org/ns/spire/sa/spire-agent
TTL           : 3600
Selector      : k8s:container-name:envoy
Selector      : k8s:ns:default
Selector      : k8s:pod-label:app:frontend
Selector      : k8s:sa:default

Entry ID      : 4e37f863-302a-4b3c-a942-dc2a86459f37
SPIFFE ID     : spiffe://example.org/ns/default/sa/default/frontend-2
Parent ID     : spiffe://example.org/ns/spire/sa/spire-agent
TTL           : 3600
Selector      : k8s:container-name:envoy
Selector      : k8s:ns:default
Selector      : k8s:pod-label:app:frontend-2
Selector      : k8s:sa:default
...
```

Note that the selectors for our workloads point to the Envoy container: `k8s:container-name:envoy`. This is how we configure Envoy to perform X.509 SVID authentication on a workload's behalf.


# Part 3: Test Connections

Now that services are deployed and also registered in SPIRE, let's test the authorization that we've configured.

## Test for Successful Authentication with Valid X.509 SVIDs

The first set of testing will demonstrate how valid X.509 SVIDs allow for the display of associated data. To do this, we show that both frontend services, (`frontend` and `frontend-2`) can talk to the `backend` service by getting the correct IP address and port for each one. To run these tests, we need to find the IP addresses and ports that make up the URLs to use for accessing the data.

```console
$ kubectl get services

NAME            TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)          AGE
backend-envoy   ClusterIP      None          <none>           9001/TCP         6m53s
frontend        LoadBalancer   10.8.14.117   35.222.164.221   3000:32586/TCP   6m52s
frontend-2      LoadBalancer   10.8.7.57     35.222.190.182   3002:32056/TCP   6m53s
kubernetes      ClusterIP      10.8.0.1      <none>           443/TCP          59m
```

The `frontend` service will be available at the `EXTERNAL-IP` value and port `3000`, which was configured for our container. In the sample output shown above, the URL to navigate is `http://35.222.164.221:3000`. Open your browser and navigate to the IP address shown for `frontend` in your environment, adding the port `:3000`. Once the page is loaded, you'll see the account details for user _Jacob Marley_. 

![Frontend][frontend-view]

[frontend-view]: images/frontend_view.png "Frontend view"

Following the same steps, when you connect to the URL for the `frontend-2` service  (e.g. `http://35.222.190.182:3002`) the browser displays the account details for user _Alex Fergus_.

![Frontend-2][frontend-2-view]

[frontend-2-view]: images/frontend-2_view.png "Frontend-2 view"

## Update the TLS Configuration So Only One Frontend Can Access the Backend

The Envoy configuration for the `backend` service uses the TLS configuration to filter incoming connections by validating the Subject Alternative Name (SAN) of the certificate presented on the TLS connection. For SVIDs, the SAN field of the certificate is set with the SPIFFE ID associated with the service. So by specifying the SPIFFE IDs in the `match_subject_alt_names` filter we indicate to Envoy which services can establish a connection.

Let's now update the Envoy configuration for the `backend` service to allow requests from the `frontend` service only. This is achieved by removing the SPIFFE ID of the `frontend-2` service from the `combined_validation_context` section at the [Envoy configuration](k8s/backend/config/envoy.yaml#L49). The updated configuration looks like this:

```console
combined_validation_context:
  # validate the SPIFFE ID of incoming clients (optionally)
  default_validation_context:
    match_subject_alt_names:
      - exact: "spiffe://example.org/ns/default/sa/default/frontend"

```

## Apply the New Configuration for Envoy

To update the Envoy configuration for the `backend` workload use the file `backend-envoy-configmap-update.yaml`:

```console
$ kubectl apply -f backend-envoy-configmap-update.yaml
```

Next, the `backend` pod needs to be restarted to pick up the new configurations:

```console
$ kubectl scale deployment backend --replicas=0
$ kubectl scale deployment backend --replicas=1
```

Wait some seconds for the deployment to propagate before trying to view the `frontend-2` service in your browser again.
Once the pod is ready, refresh the browser using the correct URL for `frontend-2` service (e.g. `http://35.222.190.182:3002`). As a result, now Envoy does not allow the request to get to the `backend` service and account details are not shown in your browser.

![Frontend-2-no-details][frontend-2-view-no-details]

[frontend-2-view-no-details]: images/frontend-2_view_no_details.png "Frontend-2 view no details account"

On the other hand, you can check that the `frontend` service is still able to get a response from the `backend`. Refresh the browser at the correct URL (e.g. `http://35.222.164.221:3000`) and confirm that account details are shown for _Jacob Marley_.


# Extend the Scenario with a Role Based Access Control Filter

Envoy provides a Role Based Access Control (RBAC) HTTP filter that checks the request based on a list of policies. A policy consists of permissions and principals, where the principal specifies the downstream client identities of the request, for example, the URI SAN of the downstream client certificate. So we can use the SPIFFE ID assigned to the service to create policies that allow for more granular access control.

The `Symbank` demo application consumes three different endpoints to get all the information about the bank account. The `/profiles` endpoint provides the name and the address of the account's owner. The other two endpoints, `/balances` and `/transactions`, provide the balance and transactions for the account.

To demonstrate an Envoy RBAC filter, we can create a policy that allows the `frontend` service to obtain only data from the `/profile` endpoint and deny requests sent to other endpoints. This is achieved by defining a policy with a principal that matches the SPIFFE ID of the service and the permissions to allow only GET requests to the `/profiles` resource.

The following snippet can be added to the Envoy configuration for the `backend` service as a new HTTP filter to test the policy.

```console
- name: envoy.filters.http.rbac
  config:
    rules:
      action: ALLOW
      policies:
        "general-rules":
          permissions:
              - and_rules:
                  rules:
                    - header: { name: ":method", exact_match: "GET" }
                    - url_path:
                        path: { prefix: "/profiles" }
          principals:
          - authenticated:
              principal_name:
                exact: "spiffe://example.org/ns/default/sa/default/frontend"
```

The example illustrates how to perform more granular access control based on request parameters when there is a TLS connection already established by Envoy instances which have obtained their identities from SPIRE.


# Cleanup

When you are finished running this tutorial, you can use the following script to remove all the resources used for configuring Envoy to perform X.509 authentication on workload's behalf. This command will remove:
   * All resources created for the SPIRE - Envoy X.509 integration tutorial.
   * All deployments and configurations for the SPIRE Agent, SPIRE Server, and namespace.

```console
$ bash scripts/clean-env.sh
```
