[Configure Envoy to perform X.509 SVID authentication on a workload's behalf]
[Using SPIRE to automatically deliver TLS certificates to Envoy]

# Overview

This tutorial builds on the [Kubernetes Quickstart](/spire/try/getting-started-k8s/) guide to describe how to configure SPIRE to provide service identity dynamically in the form of X.509 certificates that will be consumed by Envoy secret discovery service (SDS).

To illustrate it, we'll create a simple scenario with three services. One service will be the back end that is a simple nginx instance serving static data. On the other side, we run two instances of the `Symbank` demo application acting as the front-end services. The `Symbank` simulates a user bank account and sends http requests to the backend to get the user account details. 

![SPIRE Envoy integration diagram][diagram]

[diagram]: images/SPIRE_Envoy_diagram.png "SPIRE Envoy integration diagram"

As states in the diagram, the front-end services connect to the back-end service via a mTLS connection established by the Envoy instances that perform X.509 SVID authentication on workload's behalf.


In this tutorial you will learn how to:

* Set up SDS support in SPIRE
* Configure Envoy SDS to consume X.509 certificates provided by SPIRE


# Prerequisites

Before proceeding, review the following:

* You'll need access to the Kubernetes environment that you configured when going through [Kubernetes Quickstart](/spire/try/getting-started-k8s/). The Kubernetes environment must be able to expose an Ingress to the public internet. _Note: This is generally not true for local Kubernetes environments such as Minikube._

* Required YAML files for this tutorial can be found in the `k8s/envoy-x509` directory from the repository https://github.com/spiffe/spire-tutorials cloned as part of the Kubernetes Quickstart guide.


If that environment is not available any more, you can use the following commands to recreate it and use it as start point for this tutorial

```console
   $ kubectl apply -k ../quickstart/.
```

Wait until all pods are running before continuing to the next step

```console
   $ kubectl -n spire get pods
```

Finally, create a registration entry for the agent

```console
   $ bash ../quickstart/create-node-registration-entry.sh
```


# Part 1: Update SPIRE Agent to support SDS

As we want Envoy to consume certificates via SDS we need to configure SPIRE to provide them by enabling the SDS support on our SPIRE Agent.  The `spire-agent-configmap.yaml` file in the `k8s/envoy` directory includes a new line to enable SDS support

 `enable_sds: true`

Change to the local directory that includes the `k8s/envoy` files and apply the new config map for the SPIRE Agent:

   ```console
   $ kubectl apply -f spire-agent-configmap.yaml
   ```

Delete the SPIRE Agent pod so it is restarted using the new configuration provided in the previous step.

```console
 $ kubectl -n spire delete pod $(kubectl -n spire get pods --selector=app=spire-agent --output=jsonpath="{..metadata.name}")
```

Check `spire-agent` status and when the pod displayed as **_Running_**, continue to the next step.

  ```console
  $ kubectl -n spire get pod --selector=app=spire-agent
  ```


# Part 2: Run workloads

Now we deploy the workloads we'll use in this tutorial. It consists of three workloads, as mentioned before, two instances of the `Symbank` demo application will act as front-end services and the other, an instance of _nginx_ serving static files, will be the back-end service.
To make a distinction between the two instances of the `Symbank` application, let's call one **frontend** and the other **frontend-2**. The former is configured to present data related to the user _Jacob Marley_ and the second will show account details for the user _Alex Fergus_.

## Deploy all workloads

Deploy the resources using:

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

Several resources have been created.
   * A Deployment for each of the workloads. It contains one container for our service plus the Envoy sidecar.
   * A Service for each workload. It is used to communicate between them.
   * Several Configmaps:
      * _*-json-data_ are used to provide static files to the _nginx_ instance running as the backend service
      * _*-envoy_ contains the envoy configuration for each workload.
      * _symbank-webapp-*_ contains the configuration supplied to each instance of the front-end services.


Let's focus on the envoy configuration for the backend service. This is where the details are set in order to let Envoy SDS to consume X.509 certificates provided by SPIRE. The configuration is located at `k8s/backend/config/envoy.yaml`.

### SPIRE Agent Cluster

Envoy must be configured to communicate with the SPIRE Agent. This is achieved by configuring a cluster that points to the Unix domain socket the SPIRE Agent provides.

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
              verify_subject_alt_name:
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

Similar configurations are set on the both front-end services to establish a TLS communication. Check the configuration of the cluster named `backend` on `k8s/frontend/config/envoy.yaml` and `k8s/frontend-2/config/envoy.yaml`

## Create registration entries

In order to get X509 certificates issued by SPIRE we need to register our workloads. We can achieve this by creating registration entries for each of our workloads. Let's use the following bash script:

   ```console
   $ bash create-registration-entries.sh
   ```

Once the script is run, the list of created registration entries will be shown. Note that there are other registration entries created at the [Kubernetes Quickstart](/spire/try/getting-started-k8s/) guide. The important ones here are the three new belonging to each of our workloads:

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

Note that the selectors for our workloads points to the envoy container: `k8s:container-name:envoy`. This is how we configure Envoy to perform X.509 SVID authentication on a workload's behalf.


# Part 3: Test connections
We have deployed our services and also registered them in SPIRE. Now we can check that both front-end services con talk to our backend service by getting the correct IP address and port for each one.

   ```console
   $ kubectl get services

   NAME            TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)          AGE
   backend-envoy   ClusterIP      None          <none>           9001/TCP         6m53s
   frontend        LoadBalancer   10.8.14.117   35.222.164.221   3000:32586/TCP   6m52s
   frontend-2      LoadBalancer   10.8.7.57     35.222.190.182   3002:32056/TCP   6m53s
   kubernetes      ClusterIP      10.8.0.1      <none>           443/TCP          59m
   ```

The **frontend** service we'll be available at `EXTERNAL-IP` value and port `3000`, which was configured for our container. In this case the url to navigate is `35.222.164.221:3000`. Open your browser and navigate to the correct url for your environment. Once the page is loaded, you'll see the details account for user _Jacob Marley_. 

![Frontend][frontend-view]

[frontend-view]: images/frontend_view.png "Frontend view"

Following the same steps we can confirm that the **frontend-2** service is also able to talk to the backend service. In this case the url is `35.222.190.182:3002` and once the page is loaded, you'll see the details for user _Alex Fergus_

![Frontend-2][frontend-2-view]

[frontend-2-view]: images/frontend-2_view.png "Frontend-2 view"


## Update RBAC rules so only one front end can access the backend
Envoy configuration for our **backend** service includes a simple RBAC rule to allow any action from only two authenticated principals. Both principals are our front-end workloads.
Let's now update the Envoy configuration for our **backend** workload so we only allow requests from one of the front-end services.

We'll accomplish this by removing one of the `principals` listed on the RBAC rule. In this case, let's remove **frontend-2**. The updated rule looks like this:

   ```console
      http_filters:
      - name: envoy.filters.http.rbac
         config:
         rules:
            action: ALLOW
            policies:
               "general-rules":
               permissions:
                  - any: true
               principals:
               - authenticated:
                     principal_name:
                     exact: "spiffe://example.org/ns/default/sa/default/frontend"
   ```

### Apply new configuration
To update the Envoy configuration for our backend workload we use `backend-envoy-configmap-rbac-update.yaml` file:

   ```console
   $ kubectl apply -f backend-envoy-configmap-rbac-update.yaml
   ```
And now let's delete the backend pod so it is recreated using the new configuration

   ```console
   $ kubectl delete pod $(kubectl get pods --selector=app=backend --output=jsonpath="{..metadata.name}")
   ```

Wait some seconds until de pods is running and ready before trying to hit the backend via frontend-2 service again.
Once the pod is ready, refresh the browser on the correct url for the **frontend-2** service. In this case `35.222.190.182:3002`. As a result we can see that Envoy did not allow the request to get to the backend so the web page it is only showing the title without any account details.

![Frontend-2-no-details][frontend-2-view-no-details]

[frontend-2-view-no-details]: images/frontend-2_view_no_details.png "Frontend-2 view no details account"


On the other hand, you can check that the **frontend** service is still able to get a response from the **backend**. Refresh the browser at the correct url, in this case `35.222.164.221:3000`, and confirm that user details for _Jacob Marley_ are displayed.


# Cleanup

When you are finished running this tutorial, you can use the following commands to remove all the resources used for Envoy integration and the SPIRE setup.

## Kubernetes Cleanup

Keep in mind that these commands will also remove the setup that you configured in the [Kubernetes Quickstart](/spire/try/getting-started-k8s/).

1. Delete all resources created for this SPIRE - Envoy integration tutorial:

   ```console
   $ kubectl delete -k k8s/.
   ```

2. Delete all deployments and configurations for the SPIRE agent, SPIRE server, and namespace:

If you created the SPIRE setup as part of this tutorial, you can clean the environment by running:
   ```console
   $ kubectl delete -k ../quickstart/.
   ```
 On the other hand, if the SPIRE setup belongs to the [Kubernetes Quickstart](/spire/try/getting-started-k8s/) guide and you want to clean the environment, you can run the following commands:

  ```console
   $ kubectl delete namespace spire
   ```

And then delete the ClusterRole and ClusterRoleBinding settings:

   ```console
   $ kubectl delete clusterrole spire-server-trust-role spire-agent-cluster-role
   $ kubectl delete clusterrolebinding spire-server-trust-role-binding spire-agent-cluster-role-binding
   ```
