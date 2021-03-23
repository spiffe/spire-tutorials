# Configure SPIRE to use the Kubernetes Workload Registrar
This tutorial builds on the [Kubernetes Quickstart Tutorial](../quickstart/) and provides an example of how to configure SPIRE to use the Kubernetes Workload Registrar as a container within the SPIRE Server pod. With this tool, automatic workload registration and management is added to SPIRE. The changes required to deploy the registrar and the necessary files are shown as a delta to the quickstart tutorial, so it is highly encouraged to execute, or at least read through, the Kubernetes Quickstart Tutorial first.

In this document you will learn how to:
* Deploy the K8s Workload Registrar as a container within the SPIRE Server Pod
* Configure the 3 available modes and their differences 
* Use the 3 available workload registration modes
* Test successful registration entries creation

# Prerequisites
Before proceeding, review the following list:
* You'll need access to the Kubernetes environment configured when going through the [Kubernetes Quickstart Tutorial](../quickstart/).
* Required configuration files for this tutorial can be found in the `k8s/k8s-workload-registrar` directory in https://github.com/spiffe/spire-tutorials. If you didn't already clone the repo for the _Kubernetes Quickstart Tutorial_, please do so now.
* The steps in this document should work with Kubernetes version 1.20.2.

We will deploy an scenario that consists of a statefulset containing a SPIRE Server and the Kubernetes Workload Registrar, a SPIRE Agent, and a workload, and configure the different modes to illustrate the automatic registration entries creation.

# Common configuration

The SPIRE Server and the Kubernetes Workload registrar will communicate each other using a socket, that will be mounted at the `/tmp/spire-server/private` directory, as we can see from the `volumeMounts` section of both containers. The only difference between these sections is that, for the registrar, the socket will have the `readOnly` option set to `false`, while for the SPIRE Server container it will have its value set to `true`. Below, this section is shown for the registrar container.

```
- name: spire-server-socket
  mountPath: /tmp/spire-server/private
  readOnly: true
```

# Webhook mode (default)

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

This webhook itself authenticates the API server, and for this reason we provide a CA bundle, with the `caBundle` option, as we can see in the stanza above (value ommited for brevity). This authentication must be done to ensure that it is the API server who is contacting the webhook, because this situation will lead to registration entries creation or deletion on the SPIRE Server, something that is a key point in the SPIRE infrastructure.

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

The certificates for the CA and for the server are stored in a `ConfigMap`:

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
    cert_path = "/run/spire/k8s-workload-registrar/certs/server-cert.pem"
    key_path = "/run/spire/k8s-workload-registrar/secret/server-key.pem"
    cacert_path = "/run/spire/k8s-workload-registrar/certs/cacert.pem"
    trust_domain = "example.org"
    cluster = "k8stest"
    server_socket_path = "/tmp/spire-server/private/api.sock"
    insecure_skip_client_verification = false
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

To be mounted, an `AdmissionConfiguration` describes where the API server can locate the file containing the `KubeConfig` entry. This file is passed to the API server via the `--extra-config=apiserver.admission-control-config-file` flag.

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

We have looked at the key points of the webhook mode's configuration, so let's apply the necessary files to set our scenario with a SPIRE Server with the registrar container in it, an Agent, and a workload, by issuing the following command:

```console
$ insert command to deploy the scenario for the webhook mode
```

This is all we need to have the registration entries created on the server. We will start a shell into the SPIRE Server container and run the entry show directive by executing the command below:

```console
$ insert command to see registration entries
```

You should see the following 3 registration entries, corresponding to the node, the agent, and the workload.

***insert reg entries*** 

Let's see how are they built:

The cluster name is used as Parent ID, and there is no reference to the node that the pod belongs to, this is, all the registration entries are mapped to a single node entry inside the cluster. This represents a drawback for this mode, as all the nodes in the cluster have permission to get identities for all the workloads that belong to the Kubernetes cluster, which increases the blast ratio in case of a node being compromised, among other disadvantages.

Taking a look on the assigned SPIFFE IDs for the agent and the workload, we can see that they have the following form:
*spiffe://\<TRUSTDOMAIN\>/ns/\<NAMESPACE\>/sa/\<SERVICEACCOUNT\>*.
From this, we can conclude that we are using the registrar configured with the Service Account Based workload registration (which is the default behaviour). For instance, as the workload uses the *default* service account, into the *spire* namespace, its SPIFFE ID is: *spiffe://example.org/ns/spire/sa/default* 

Another thing that is worth looking, is the registrar log, in which we will found out if the entries were created by this container. Run the following command to get the logs of the registrar, and to look for the *Created pod entry* keyword. 

***insert command to get the logs and grep over the desired keyword***

The result should be similar to the one shown below:

***insert output of the command above***

We can check that the 3 entries that were present on the SPIRE Server were created by the registrar, and correspond to the node, agent, and workload, in that specific order.

## Pod deletion

Let's see how the registrar handles a pod deletion, and which impact does it have on the registration entries. Run the following command to delete the workload deployment: 

```console
$ insert command to delete workload pod
```
Again, check for the registration entries with the command below:

```console 
$ insert command to see registration entries
```

The output of the command will not include the registration entry that correspond to the workload, because the pod was deleted, and should be similar to this:

***insert reg entries*** 

As the pod was deleted, we will check the registrar logs, looking for the "Deleted pod entry" keyword, with the command shown below:

```console 
$ insert command to get the logs and grep over the desired keyword
```

The output should be similar to:

***insert output of the command above***

From which we can conclude that the registrar successfuly deleted the corresponding entry of the recently deleted pod.

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
    mode = "reconcile"
    trust_domain = "example.org"
    cluster = "k8stest"
    server_socket_path = "/tmp/spire-server/private/api.sock"
    metrics_addr = "0"
    pod_label = "spire-workload"
```

We are explicitly indicating that *reconcile* mode is used. For the sake of the tutorial, we will be using Label Based workload registration for this mode (as we can see from the `pod_label` configurable), though every workload registration mode can be used with every registrar mode. This is all the configuration that is needed to have the containers working properly.

We will deploy the same scenario as the previous mode, with the difference on the agent and workload pods: they will be labeled with the *spire-workload* label, that corresponds to the value indicated in the `pod_label` option of the `ConfigMap` shown above. Run the following command to set the scenario:

```console
$ insert command to deploy the scenario for the reconcile mode
```

With the Reconcile scenario set, we will check the registration entries and some special considerations for this mode. Let's issue the command below to start a shell into the SPIRE Server container, and to show the existing registration entries.

```console
$ insert command to see registration entries
```

Your output should similar to the following, and shows the entries for the node, the agent and the workload:

***insert reg entries***

If we compare this entries to the Webhook mode ones, the difference is that the Parent ID of the SVID contains a reference to the node name where the pod is scheduled on. We mentioned that this is not happening using the Webhook node, and this was one of its principal drawbacks. Also, for the node registration entry (the one that has the SPIRE Server SPIFFE ID as the Parent ID), node name is used in the selectors, along with the cluster name. For the remaining two entries, pod name and namespace are used in the selectors instead.

As we are using Label workload registration mode, the SPIFFE ID's for the agent and the workload (which are labeled as we mentioned before) have the form: *spiffe://\<TRUSTDOMAIN\>/\<LABELVALUE\>*. For example, as the agent has the label value equal to `agent`, it has the following SPIFFE ID: *spiffe://example.org/agent*.

Let's check if the registrar indeed created the registration entries, by checking its logs, and looking for the *Created new spire entry* keyword. Run the command that is shown below:

```console
$ insert command to see the registrar logs
```

The output will be similar to this:

***insert output of show logs command***

We mentioned before that there were two reconciling controllers, and we are seeing now that the node controller created the entry for the single node in the cluster, and that the pod controller created the entries for the two labeled pods: agent and workload.

## Pod deletion

The Kubernetes Workload Registrar automatically handles the creation and deletion of registration entries. We already see how the entries are created, and now we will test its deletion. Let's delete the workload deployment: 

```console
$ insert command to delete workload deployment
```

We will check if its corresponding entry is deleted too. Run the following command to see the registration entries on the SPIRE Server:

```console
$ insert command to see registration entries
```

The output will only show two registration entries, because the workload entry was deleted by the registrar:

***insert reg entries***

If we look for the *Deleted entry* keyword on the registrar logs, we will find out that the registrar deleted the entry. Issue the following command:

```console
$ insert command to see registrar logs
```

The output should be similar to: 

***insert output of above command***

The registrar successfuly deleted the entry.

## Non-labeled pods

As we are using Label Based workload registration, only pods that have the label *spire-workload* will have its registration entry automatically created. Let's deploy a pod that has no label with the command below:

```console
$ insert command to deploy a non-labeled workload
```

Let's see the existing registration entries with the command:

```console
$ insert command to see registration entries
```

It's output should be similar to: 

***insert reg entries***

We see that the entries are the same as before, and that no entry has been created for the new workload. This is the expected behaviour, as only labeled pods will be considered by the workload registrar while using the Label Workload registration mode.

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
    cluster = "k8stest"
    mode = "crd"
    pod_annotation = "spiffe.io/spiffe-id"
```

Let's deploy the necessary files, including the base scenario plus the SPIFFE ID CRD definition, and examine the automatically created registration entries.

```console
$ insert command to deploy the crd mode scenario
```

Start a shell into the SPIRE Server and run the entry show command by executing:

```console
$ insert command to see registration entries
```

The output should show the following registration entries:

***insert reg entries***

3 entries were created corresponding to the node, agent, and workload. For the node entry (the one that has the SPIRE Server SPIFFE ID as Parent ID), we see a difference in the selectors, comparing it with the selectors in the node entry created using Reconcile mode: we find out that instead of placing the node name, CRD mode stores the UID of the node where the agent is running on. As the node name is used in the SPIFFE ID assigned to the node, we can take this as a mapping from node UID to node name.

Something similar happens with the pod entries, but this time the pod UID where the workload is running is stored in the selectors, instead of the node UID.

If we now focus our attention on the SPIFFE IDs assigned to the workloads, we see that it takes the form of *spiffe://\<TRUSTDOMAIN\>/\<ANNOTATIONVALUE\>*. By using Annotation Based workload registration, it is possible to freely set the SPIFFE ID path. In this case, for the workload, we set the annotation value to *example-workload*.

## Pod deletion

As in the previous modes, if we delete the workload deployment, we will see that its corresponding registration entry will be deleted too. Let's run the command to delete the workload pod: 

```console
$ insert command to delete workload deployment
```

And now, check the registration entries in the SPIRE Server by executing:

```console
insert command to see registration entries
```

The output should look like:

***insert registration entries***

The only entries that should exist now are the ones that match the node and the SPIRE agent, because the workload one was deleted by the registrar.

## Non-annotated pods

Let's check if a pod that has no annotations its considered by the registrar. Deploy a new workload with this condition with the following command:

```console
$ insert command to deploy a workload with no annotation
```

As in the previous section, let's see the registration entries that are present in the SPIRE Server:

```console
insert command to see registration entries
```

The result of the command should be equal to the one shown in *Pod deletion* section, because no new entry has been created, as expected.

## SPIFFE ID CRD creation

One of the benefits of using CRD Mode is that we can manipulate the SPIFFE IDs as if they were resources inside Kubernetes environment, in other words using the *kubectl* command.

If we check for SPIFFE IDs resources (using *kubectl get spiffeids -n spire*), we'll obtain something like the following:

***insert the spiffeids resources***

From this we can see that there are 2 already created custom resources, corresponding to the 3 entries that we saw above, minus the one for the workload, whose pod was deleted in the *Pod deletion* section.

Let's create a new SPIFFE ID CRD by using:

```console
# insert command to create a spiffe id crd
``` 

We will check if it was created, executing the *kubectl get spiffeids -n spire* command, whose output will show 3 custom resources: 

***insert output of spiffeids resources after applying the spiffeid***

The resource was succesfully created, but had it any impact on the SPIRE Server? Let's execute the command below to see the registration entries:

```console
$ insert command to see registration entries
```

You'll get an output similar to this:

***insert reg entries***

As we can see, a SPIFFE ID CRD creation triggers a registration entry creation on the SPIRE Server too. 

## SPIFFE ID CRD deletion

The lifecycle of a SPIFFE ID CRD can be managed by Kubernetes, and has a direct impact on the corresponding registration entry stored in the SPIRE Server. We already see how a SPIFFE ID CRD creation activates a registration entry one. We will prove that the same applies for a CRD deletion.

Let's delete the previously created SPIFFE ID CRD, and later check for the registration entries on the server. Run the following command to delete the CRD:

```console
$ insert command to delete a spiffe id crd
```

Now, we will check the registration entries:

```console
$ insert command to see reg entries on spire server
```

The output from this command should look like:

***insert reg entries***

As we can see, the corresponding registration entry was deleted on the SPIRE Server too.
