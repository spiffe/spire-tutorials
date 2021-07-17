# Configure SPIRE to use the Kubernetes Workload Registrar
 This tutorial provides an example of how to configure the SPIRE Kubernetes Workload Registrar as a container within the SPIRE Server pod using a local cluster deployed with [kind](https://kind.sigs.k8s.io/). The registrar enables automatic workload registration and management in SPIRE Kubernetes implementations. It is highly encouraged to execute, or at least read through, the [Kubernetes Quickstart Tutorial](../quickstart/) to fully understand this tutorial as a similar deployment is used here.

This tutorial demonstrates how to use the registrar's three different modes:

 * Webhook - For historical reasons, the webhook mode is the default but reconcile and CRD modes are now preferred because webhook can create StatefulSets and pods with no entries and cause other cleanup and scalability issues.
 * Reconcile - The reconcile mode uses reconciling controllers rather than webhooks. It may may be slightly faster to create new entries than CRD mode and requires less configuration.
 * CRD - The CRD mode provides a namespaced SpiffeID custom resource and is best for cases where you plan to manage SpiffeID custom resources directly.

See the [Differences between modes](https://github.com/spiffe/spire/tree/master/support/k8s/k8s-workload-registrar#differences-between-modes) section of the GitHub README for more information.

In this document you will learn how to:
 * Deploy the K8s Workload Registrar as a container within the SPIRE Server Pod
 * Configure the three workload registration modes
 * Use the three workload registration modes
 * Test successful registration entries creation

For documentation about SPIRE Kubernetes Workload Registrar configuration options, see the [GitHub README](https://github.com/spiffe/spire/tree/master/support/k8s/k8s-workload-registrar).

 # Prerequisites
 Before proceeding, review the following list:
 * It is recommended to go through the [Kubernetes Quickstart Tutorial](../quickstart/) before proceeding with the steps described in this guide.
 * Required configuration files for this tutorial can be found in the `k8s/k8s-workload-registrar` directory in [https://github.com/spiffe/spire-tutorials](https://github.com/spiffe/spire-tutorials).
 * The steps in this document should work with Kubernetes version 1.20.2.

We will deploy an scenario that consists of a StatefulSet containing a SPIRE Server and the Kubernetes Workload Registrar, a SPIRE Agent, and a workload, and configure the different modes to illustrate the automatic registration entries creation.

# Common configuration

Below, we describe parts of the configurations that are common to the three modes.

The SPIRE Server and the Kubernetes Workload registrar will communicate each other using a socket, that will be mounted at the `/tmp/spire-server/private` directory, as we can see from the `volumeMounts` section of both containers. The only difference between these sections is that, for the registrar, the socket will have the `readOnly` option set to `true`, while for the SPIRE Server container it will have its value set to `false`. The registrar container's section that illustrate what we described earlier is shown:

```
volumeMounts:
- name: spire-server-socket
  mountPath: /tmp/spire-server/private
  readOnly: true
```

# Webhook mode (default)

In this section we will review the important files needed to configure Webhook mode.

This mode makes use of the `ValidatingWebhookConfiguration` feature from Kubernetes, which is called by the Kubernetes API server everytime a new pod is created or deleted in the cluster, as we can see from the rules of the resource below:

```
ApiVersion: admissionregistration.k8s.io/v1beta1
kind: ValidatingWebhookConfiguration
metadata:
  name: k8s-workload-registrar-webhook
webhooks:
  - name: k8s-workload-registrar.spire.svc
    clientConfig:
      service:
        name: k8s-workload-registrar
        namespace: spire
        path: "/validate"
      caBundle: ...
    admissionReviewVersions:
    - v1beta1
    rules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "DELETE"]
      resources: ["pods"]
      scope: "Namespaced"
```

This webhook itself authenticates the API server, and for this reason we provide a CA bundle, with the `caBundle` option, as we can see in the stanza above (value ommited for brevity). This authentication must be done to ensure that it is the API server who is contacting the webhook, because this situation will lead to registration entries creation or deletion on the SPIRE Server, something that is a key point in the SPIRE infrastructure, and should be tightly controlled.

Also, a secret is volume mounted in the `/run/spire/k8s-workload-registrar/secret` directory inside the SPIRE Server container, containing the K8S Workload Registrar server key. We can see this in the `volumeMounts` section of the SPIRE Server statefulset configuration file:

```
- name: k8s-workload-registrar-secret
  mountPath: /run/spire/k8s-workload-registrar/secret
  readOnly: true
```

The secret itself is named `k8s-workload-registrar-secret` and is shown below:

```
apiVersion: v1
kind: Secret
metadata:
  name: k8s-workload-registrar-secret
  namespace: spire
type: Opaque
data:
  server-key.pem: ...
```

Again, the value of the key is ommited.

Another configuration that is relevant in this mode is the registrar certificates `ConfigMap`, that contains the K8S Workload Registrar server certificate and CA bundle used to verify the client certificate presented by the API server. This is mounted in the `/run/spire/k8s-workload-registrar/certs` directory. We can also check this by seeing the `volumeMounts` section of the SPIRE Server statefulset configuration file, which is shown below:  

```
- name: k8s-workload-registrar-certs
  mountPath: /run/spire/k8s-workload-registrar/certs
  readOnly: true
```

This certificates are stored in a `ConfigMap`:

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-workload-registrar-certs
  namespace: spire
data:
  server-cert.pem: |
    -----BEGIN CERTIFICATE-----

    ...

    -----END CERTIFICATE-----

  cacert.pem: |
    -----BEGIN CERTIFICATE-----

    ...

    -----END CERTIFICATE-----
```

With all of this set, we can look at at the registrar's container configuration:

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-workload-registrar
  namespace: spire
data:
  k8s-workload-registrar.conf: |
    trust_domain = "example.org"
    server_socket_path = "/tmp/spire-server/private/api.sock"
    cluster = "example-cluster"
    mode = "webhook"
    cert_path = "/run/spire/k8s-workload-registrar/certs/server-cert.pem"
    key_path = "/run/spire/k8s-workload-registrar/secret/server-key.pem"
    cacert_path = "/run/spire/k8s-workload-registrar/certs/cacert.pem"
``` 

As we can see, the `key_path` points to where the secret containing the server key is mounted, which was shown earlier. The `cert_path` and `cacert_path` points to the directory where the `ConfigMap` with the PEM encoded certificates for the server and for the CA are mounted. When the webhook is triggered, the registrar acts as the server and validates the identity of the client, which is the Kubernetes API server in this case. We can disable this authentication by setting the ```insecure_skip_client_verification``` option to `true` (though it is not recommended).

For the authentication, a `KubeConfig` file with the client certificate and key the API server should use to authenticate with the registrar is mounted inside the filesystem of the Kubernetes node. This file is shown below:

```
apiVersion: v1
kind: Config
users:
- name: k8s-workload-registrar.spire.svc
  user:
    client-certificate-data: ...
    client-key-data: ...
```

An `AdmissionConfiguration` is mounted inside the node too, and it describes where the API server can locate the file containing the `KubeConfig` entry used in the authentication process.

```
apiVersion: apiserver.k8s.io/v1alpha1
kind: AdmissionConfiguration
plugins:
- name: ValidatingAdmissionWebhook
  configuration:
    apiVersion: apiserver.config.k8s.io/v1alpha1
    kind: WebhookAdmission
    kubeConfigFile: /etc/kubernetes/pki/admctrl/kubeconfig.yaml
```

To mount the two files into the node, we will use the special option `extraMounts` of kind, that allows us to pass files between the host and a kind node. 

```
nodes:
- role: control-plane
  extraMounts:
  - containerPath: /etc/kubernetes/pki/admctrl
    hostPath: WEBHOOKDIR/k8s/admctrl
```

The ```WEBHOOKDIR/k8s/admctrl``` variable points to the folder host path where the files are stored, and `containerPath` specify the directory in which the files will be mounted.

In kind's specific configuration file (`kind-config.yaml`), we use the `admission-control-config-file` option to tell the API server where to find the admission configuration. Note that this value match with the one set in `ContainerPath`.

```
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
kubeadmConfigPatches:
- |
  apiVersion: kubeadm.k8s.io/v1beta2
  kind: ClusterConfiguration
  metadata:
    name: config
  apiServer:
    extraArgs:
        "service-account-signing-key-file": "/etc/kubernetes/pki/sa.key"
        "service-account-issuer": "api"
        "service-account-api-audiences": "api,spire-server"
        "admission-control-config-file": "/etc/kubernetes/pki/admctrl/admission-control.yaml"
...
```

We have looked at the key points of the webhook mode's configuration, so let's apply the necessary files to set our scenario with a SPIRE Server with the registrar container in it, an Agent, and a workload, by issuing the following command in the `mode-webhook` directory:

```console
$ bash scripts/deploy-scenario.sh
```

This will create a new kubernetes cluster for us, and apply the necessary files for the scenario to work. This is all we need to have the registration entries created on the server. We will run the server command to see the registration entries created, by executing the command below:

```console
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

You should see the following 3 registration entries, corresponding to the node, the agent, and the workload (the order of the results may differ with your output).

```console
Found 3 entries
Entry ID         : ...
SPIFFE ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node
Parent ID        : spiffe://example.org/spire/server
Revision         : 0
TTL              : default
Selector         : k8s_psat:cluster:example-cluster

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/ns/spire/sa/spire-agent
Parent ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node
Revision         : 0
TTL              : default
Selector         : k8s:ns:spire
Selector         : k8s:pod-name:spire-agent-wtx7b

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/ns/spire/sa/default
Parent ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node
Revision         : 0
TTL              : default
Selector         : k8s:ns:spire
Selector         : k8s:pod-name:example-workload-6877cd47d5-2fmpq
```

We omitted the entry ids, as it may change with every run. Let's see how the other fields are built:

The cluster name *example-cluster* is used as Parent ID for the entries that correspond to the agent and the workload, but there is no reference to the node that this pods belong to, this is, the registration entries are mapped to a single node entry inside the cluster. This represents a drawback for this mode, as all the nodes in the cluster have permission to get identities for all the workloads that belong to the Kubernetes cluster, which increases the blast radius in case of a node being compromised, among other disadvantages.

Taking a look on the assigned SPIFFE IDs for the agent and the workload, we can see that they have the following form:
*spiffe://\<TRUSTDOMAIN\>/ns/\<NAMESPACE\>/sa/\<SERVICEACCOUNT\>*.
From this, we can conclude that we are using the registrar configured with the Service Account Based workload registration (which is the default behaviour). For instance, as the workload uses the *default* service account, into the *spire* namespace, its SPIFFE ID is: *spiffe://example.org/ns/spire/sa/default* 

Another thing that is worth to examine is the registrar log, in which we will found out if the entries were created by this container. Run the following command to get the logs of the registrar, and to look for the *Created pod entry* keyword. 

```console
$ kubectl logs statefulset/spire-server -n spire -c k8s-workload-registrar | grep "Created pod entry"
```

The output of this command includes 3 lines, one for every entry created, and we can conclude that the 3 entries that were present on the SPIRE Server were created by the registrar. They correspond to the node, agent, and workload, in that specific order.

## Pod deletion

Let's see how the registrar handles a pod deletion, and which impact does it have on the registration entries. Run the following command to delete the workload deployment: 

```console
$ kubectl delete deployment/example-workload -n spire
```

Again, check for the registration entries with the command below:

```console 
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

The output of the command will not include the registration entry that correspond to the workload, because the pod was deleted, and should be similar to:

```console
Found 2 entries
Entry ID         : ...
SPIFFE ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node
Parent ID        : spiffe://example.org/spire/server
Revision         : 0
TTL              : default
Selector         : k8s_psat:cluster:example-cluster

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/ns/spire/sa/spire-agent
Parent ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node
Revision         : 0
TTL              : default
Selector         : k8s:ns:spire
Selector         : k8s:pod-name:spire-agent-wtx7b
```

We will check the registrar logs to find out if the registrar deleted the entry, looking for the "Deleted pod entry" keyword, with the command shown below:

```console 
$ kubectl logs statefulset/spire-server -n spire -c k8s-workload-registrar | grep "Deleting pod entries"
```

The registrar successfuly deleted the corresponding entry for the *example-workload* pod.

## Teardown

To delete the resources used for this mode, we will delete the cluster by executing:

```console
kind delete cluster --name example-cluster
```

# Reconcile mode

This mode, as opposed to Webhook mode, does not use a validating webhook but two reconciling controllers instead: one for the nodes and one for the pods. For this reason, we will not deploy all the configuration needed to perform the Kubernetes API server authentication, as the secret and `KubeConfig` entry, for instance, situation that makes the configuration simpler. 

We will jump directly into the registrar's container configuration, which is shown below:

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-workload-registrar
  namespace: spire
data:
  k8s-workload-registrar.conf: |
    trust_domain = "example.org"
    server_socket_path = "/tmp/spire-server/private/api.sock"
    cluster = "example-cluster"
    mode = "reconcile"
    pod_label = "spire-workload"
    metrics_addr = "0"
```

We are explicitly indicating that *reconcile* mode is used. For the sake of the tutorial, we will be using Label Based workload registration for this mode (as we can see from the `pod_label` configurable), though every workload registration mode can be used with every registrar mode. This is all the configuration that is needed to have the containers working properly.

We will deploy the same scenario as the previous mode, with the difference on the agent and workload pods: they will be labeled with the *spire-workload* label, that corresponds to the value indicated in the `pod_label` option of the `ConfigMap` shown above. Ensure that your working directory is `mode-reconcile` and run the following command to set the scenario:

```console
$ bash scripts/deploy-scenario.sh
```

With the Reconcile scenario set, we will check the registration entries and some special considerations for this mode. Let's issue the command below to start a shell into the SPIRE Server container, and to show the existing registration entries.

```console
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

Your output should similar to the following, and shows the entries for the node, the agent and the workload:

```console
Found 3 entries
Entry ID         : ...
SPIFFE ID        : spiffe://example.org/spire-k8s-registrar/example-cluster/node/example-cluster-control-plane
Parent ID        : spiffe://example.org/spire/server
Revision         : 0
TTL              : default
Selector         : k8s_psat:agent_node_name:example-cluster-control-plane
Selector         : k8s_psat:cluster:example-cluster

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/agent
Parent ID        : spiffe://example.org/spire-k8s-registrar/example-cluster/node/example-cluster-control-plane
Revision         : 0
TTL              : default
Selector         : k8s:ns:spire
Selector         : k8s:pod-name:spire-agent-c5c5f

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/example-workload
Parent ID        : spiffe://example.org/spire-k8s-registrar/example-cluster/node/example-cluster-control-plane
Revision         : 0
TTL              : default
Selector         : k8s:ns:spire
Selector         : k8s:pod-name:example-workload-b98cc787d-kzxz6
```

If we compare this entries to those created using Webhook mode, the difference is that the Parent ID of the SVID contains a reference to the node name where the pod is scheduled on, in this case, `example-cluster-control-plane`. We mentioned that this doesn't happen using the Webhook node, and this was one of its principal drawbacks. Also, for the node registration entry (the one that has the SPIRE Server SPIFFE ID as the Parent ID), the node name is used in the selectors, along with the cluster name. For the remaining two entries, pod name and namespace are used in the selectors instead.

As we are using Label workload registration mode, the SPIFFE ID's for the agent and the workload (which are labeled as we mentioned before) have the form: *spiffe://\<TRUSTDOMAIN\>/\<LABELVALUE\>*. For example, as the agent has the label value equal to `agent`, it has the following SPIFFE ID: *spiffe://example.org/agent*.

Let's check if the registrar indeed created the registration entries, by checking its logs, and looking for the *Created new spire entry* keyword. Run the command that is shown below:

```console
$ kubectl logs statefulset/spire-server -n spire -c k8s-workload-registrar | grep "Created new spire entry"
```

We mentioned before that there were two reconciling controllers, and from the output of the command above, we can see that the node controller created the entry for the single node in the cluster, and that the pod controller created the entries for the two labeled pods: agent and workload.

## Pod deletion

The Kubernetes Workload Registrar automatically handles the creation and deletion of registration entries. We already see how the entries are created, and now we will test its deletion. Let's delete the workload deployment: 

```console
$ kubectl delete deployment/example-workload -n spire
```

We will check if its corresponding entry is deleted too. Run the following command to see the registration entries on the SPIRE Server:

```console
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

The output will only show two registration entries, because the workload entry was deleted by the registrar:

```console
Found 2 entries
Entry ID         : ...
SPIFFE ID        : spiffe://example.org/agent
Parent ID        : spiffe://example.org/spire-k8s-registrar/example-cluster/node/example-cluster-control-plane
Revision         : 0
TTL              : default
Selector         : k8s:ns:spire
Selector         : k8s:pod-name:spire-agent-c5c5f

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/spire-k8s-registrar/example-cluster/node/example-cluster-control-plane
Parent ID        : spiffe://example.org/spire/server
Revision         : 0
TTL              : default
Selector         : k8s_psat:agent_node_name:example-cluster-control-plane
Selector         : k8s_psat:cluster:example-cluster
```

If we look for the *Deleted entry* keyword on the registrar logs, we will find out that the registrar deleted the entry. Issue the following command:

```console
$ kubectl logs statefulset/spire-server -n spire -c k8s-workload-registrar | grep "Deleted entry"
```

The pod controller successfuly deleted the entry.

## Non-labeled pods

As we are using Label Based workload registration, only pods that have the *spire-workload* label will have its registration entry automatically created. Let's deploy a pod that has no label with the command below, by executing the comand below, from the `mode-reconcile` directory:

```console
$ kubectl apply -f k8s/not-labeled-workload.yaml
```

Let's see the existing registration entries with the command:

```console
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

The output should remain constant compared to the one that we obtained in the *Pod deletion* section. This implies that the only two registration entries on the SPIRE Server corresponds to the labeled deployed resources. This is the expected behaviour, as only labeled pods will be considered by the workload registrar while using the Label Workload registration mode.

## Teardown

To delete the resources used for this mode, we will delete the cluster by executing:

```console
kind delete cluster --name example-cluster
```

# CRD mode

This mode takes advantage of the `CustomResourceDefinition` feature from Kubernetes, which allows SPIRE to integrate with this tool and its control plane. A SPIFFE ID is defined as a custom resource, with an structure that matches the form of a registration entry. Below is a reduced example of the definition of a SPIFFE ID CRD.

```
apiVersion: spiffeid.spiffe.io/v1beta1
kind: SpiffeID
metadata:
  name: my-test-spiffeid
  namespace: default
spec:
  parentId: spiffe://example.org/spire/server
  selector:
    namespace: default
    podName: my-test-pod
  spiffeId: spiffe://example.org/test
```

The main goal of the custom resource is to track the intent of what and how the registration entries should look on the SPIRE Server, and to track any modification of these registration entries, reconciling its existence. This means that every SPIFFE ID CRD will have a matching registration entry, whose existence will be closely linked. Every modification done to the registration entry will have an impact on its corresponding SPIFFE ID CRD, and viceversa.

The `ConfigMap` for the registrar below shows that we will be using the *crd* mode, and that Annotation Based workload registration is used along with it. The annotation that the registrar will look for is *spiffe.io/spiffe-id*.

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-workload-registrar
  namespace: spire
data:
  k8s-workload-registrar.conf: |
    trust_domain = "example.org"
    server_socket_path = "/tmp/spire-server/private/api.sock"
    cluster = "example-cluster"
    mode = "crd"
    pod_annotation = "spiffe.io/spiffe-id"
    metrics_bind_addr = "0"
```

Let's deploy the necessary files, including the base scenario plus the SPIFFE ID CRD definition, and examine the automatically created registration entries. Ensure that your working directory is `mode-crd`, and run:

```console
$ bash scripts/deploy-scenario.sh
```

Run the entry show command by executing:

```console
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

The output should show the following registration entries:

```console
Found 3 entries
Entry ID         : ...
SPIFFE ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node/example-cluster-control-plane
Parent ID        : spiffe://example.org/spire/server
Revision         : 1
TTL              : default
Selector         : k8s_psat:agent_node_uid:08990bfd-3551-4761-8a1b-2e652984ffdd
Selector         : k8s_psat:cluster:example-cluster

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/testing/agent
Parent ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node/example-cluster-control-plane
Revision         : 1
TTL              : default
Selector         : k8s:node-name:example-cluster-control-plane
Selector         : k8s:ns:spire
Selector         : k8s:pod-uid:538886bb-48e1-4795-b386-10e97f50e34f
DNS name         : spire-agent-jzc8w

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/testing/example-workload
Parent ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node/example-cluster-control-plane
Revision         : 1
TTL              : default
Selector         : k8s:node-name:example-cluster-control-plane
Selector         : k8s:ns:spire
Selector         : k8s:pod-uid:78ed3fc5-4cff-476a-90f5-37d3abd47823
DNS name         : example-workload-6877cd47d5-l4hv5
```

3 entries were created corresponding to the node, agent, and workload. For the node entry (the one that has the SPIRE Server SPIFFE ID as Parent ID), we see a difference in the selectors, comparing it with the selectors in the node entry created using Reconcile mode for the same pod: we find out that instead of using the node name, CRD mode stores the UID of the node where the agent is running on. As the node name is used in the SPIFFE ID assigned to the node, we can take this as a mapping from node UID to node name.

Something similar happens with the pod entries, but this time the pod UID where the workload is running is stored in the selectors, instead of the node UID.

If we now focus our attention on the SPIFFE IDs assigned to the workloads, we see that it takes the form of *spiffe://\<TRUSTDOMAIN\>/\<ANNOTATIONVALUE\>*. By using Annotation Based workload registration, it is possible to freely set the SPIFFE ID path. In this case, for the workload, we set the annotation value to *example-workload*.

Obtain the registrar logs by issuing: 

```console
kubectl logs statefulset/spire-server -n spire -c k8s-workload-registrar | grep "Created entry"
```

This will show that the registrar created the 3 entries into the SPIRE Server.

In addition to the SPIRE entries, the registrar in this mode is configure to create the corresponding custom resources. Let's check for this using a Kubernetes native command such as:

```console
$ kubectl get spiffeids -n spire
```

This command will show the custom resources for each one of the pods:

```console
NAME                               AGE
example-cluster-control-plane      24m
example-workload-5bffcd75d-stl5w   24m
spire-agent-r86rz                  24m
```

## Pod deletion

As in the previous modes, if we delete the workload deployment, we will see that its corresponding registration entry will be deleted too. Let's check it by running the command to delete the workload pod: 

```console
$ kubectl delete deployment/example-workload -n spire
```

And now, check the registration entries in the SPIRE Server by executing:

```console
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

The output should look like:

```console
Found 2 entries
Entry ID         : ...
SPIFFE ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node/example-cluster-control-plane
Parent ID        : spiffe://example.org/spire/server
Revision         : 1
TTL              : default
Selector         : k8s_psat:agent_node_uid:08990bfd-3551-4761-8a1b-2e652984ffdd
Selector         : k8s_psat:cluster:example-cluster

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/testing/agent
Parent ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node/example-cluster-control-plane
Revision         : 1
TTL              : default
Selector         : k8s:node-name:example-cluster-control-plane
Selector         : k8s:ns:spire
Selector         : k8s:pod-uid:538886bb-48e1-4795-b386-10e97f50e34f
DNS name         : spire-agent-jzc8w
```

The only entries that should exist now are the ones that match the node and the SPIRE agent, because the workload one was deleted by the registrar, something that we can check if we examine the registrar logs, but this time looking for the keyword "Deleted entry".

```console
$ kubectl logs statefulset/spire-server -n spire -c k8s-workload-registrar | grep -A 1 "Deleted entry"
```

As the registrar handles the custom resources automatically, it also deleted the corresponding SPIFFE ID CRD, something that we can also check by querying the Kubernetes control plane (```kubectl get spiffeids -n spire```), command from which we will obtaing the following:

```console
NAME                            AGE
example-cluster-control-plane   41m
spire-agent-r86rz               40m
```

## Non-annotated pods

Let's check if a pod that has no annotations its considered by the registrar. Deploy a new workload with this condition with the following command:

```console
$ kubectl apply -f k8s/not-annotated-workload.yaml
```

As in the previous section, let's see the registration entries that are present in the SPIRE Server:

```console
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

The result of the command should be equal to the one shown in *Pod deletion* section, because no new entry has been created, as expected.

## SPIFFE ID CRD creation

One of the benefits of using the CRD Mode is that we can manipulate the SPIFFE IDs as if they were resources inside Kubernetes environment, in other words using the *kubectl* command.

Let's create a new SPIFFE ID CRD by using:

```console
$ kubectl apply -f k8s/test_spiffeid.yaml
``` 

We will check if it was created, consulting the custom resources with ```kubectl get spiffeids -n spire```, whose output will show the following: 

```console
NAME                            AGE
example-cluster-control-plane   45m
my-test-spiffeid                19s
spire-agent-r86rz               45m
```

The resource was succesfully created, but had it any impact on the SPIRE Server? Let's execute the command below to see the registration entries:

```console
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

You'll get an output similar to this:

```console
Found 3 entries
Entry ID         : ...
SPIFFE ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node/example-cluster-control-plane
Parent ID        : spiffe://example.org/spire/server
Revision         : 1
TTL              : default
Selector         : k8s_psat:agent_node_uid:08990bfd-3551-4761-8a1b-2e652984ffdd
Selector         : k8s_psat:cluster:example-cluster

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/test
Parent ID        : spiffe://example.org/spire/server
Revision         : 1
TTL              : default
Selector         : k8s:ns:spire
Selector         : k8s:pod-name:my-test-pod

Entry ID         : ...
SPIFFE ID        : spiffe://example.org/testing/agent
Parent ID        : spiffe://example.org/k8s-workload-registrar/example-cluster/node/example-cluster-control-plane
Revision         : 1
TTL              : default
Selector         : k8s:node-name:example-cluster-control-plane
Selector         : k8s:ns:spire
Selector         : k8s:pod-uid:538886bb-48e1-4795-b386-10e97f50e34f
DNS name         : spire-agent-jzc8w
```

As we can see, a SPIFFE ID CRD creation triggers a registration entry creation on the SPIRE Server too. 

## SPIFFE ID CRD deletion

The lifecycle of a SPIFFE ID CRD can be managed by Kubernetes, and has a direct impact on the corresponding registration entry stored in the SPIRE Server. We already see how a SPIFFE ID CRD creation activates a registration entry one. We will prove that the same applies for a CRD deletion.

Let's delete the previously created SPIFFE ID CRD, and later check for the registration entries on the server. Run the following command to delete the CRD:

```console
$ kubectl delete spiffeid/my-test-spiffeid -n spire
```

Now, we will check the registration entries:

```console
$ kubectl exec -it statefulset/spire-server -n spire -c spire-server -- bin/spire-server entry show -registrationUDSPath /tmp/spire-server/private/api.sock
```

The output from this command should include only the entries for the node and the agent, because the recently created SPIFFE ID CRD was deleted, along with the entry.

## Teardown

To delete the resources used for this mode, we will delete the cluster by executing:

```console
$ kind delete cluster --name example-cluster
```
