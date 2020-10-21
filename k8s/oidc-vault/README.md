# Using SPIRE and OIDC to Authenticate Workloads to Retrieve Vault Secrets

This tutorial builds on the [Kubernetes Quickstart](https://spiffe.io/spire/try/getting-started-k8s/) guide to describe how to set up OIDC Federation between a SPIRE Server and a Vault server. This will allow a SPIRE-identified workload to authenticate against a federated Vault server by presenting no more than its JWT-SVID. Using this technique the workload won't need to authenticate itself against the Vault server using another authentication method like AppRole or Username & Password.

In this tutorial you will learn how to:

* Deploy the OIDC Discovery Provider Service
* Create the required DNS A record to point to the OIDC Discovery document endpoint
* Set up a local Vault server to store secrets
* Configure a SPIRE Server OIDC provider as an authentication method for the Vault server
* Test access to secrets using a SPIRE-provided identity

## Prerequisites

Note the following required accounts, prerequisites, and limitations before starting this tutorial:

* You'll need access to the Kubernetes environment that you configured when going through [Kubernetes Quickstart](https://spiffe.io/spire/try/getting-started-k8s/). The Kubernetes environment must be able to expose an Ingress to the public internet. _Note: This is generally not possible for local Kubernetes environments such as Minikube._
* You'll need the ability to configure a DNS A record for the SPIRE OIDC Discovery document endpoint (see [Part 2](#part-2-configure-dns-for-the-oidc-discovery-provider-ip-address)).

# Part 1: Configure SPIRE Components

In the first part of this procedure, you will configure the SPIRE components in a Kubernetes deployment.

## Download Kubernetes YAML Files for this Tutorial

To get all of the files required for this tutorial, clone https://github.com/spiffe/spire-tutorials. The YAML files that describe the Kubernetes deployment are in the `k8s/oidc-vault/k8s` directory.

## Replace Placeholder Strings in YAML Files

The following strings in the YAML files must be substituted for values specific to your environment. Each location where you must make a change has been marked with `TODO:` in the YAML files.
 
| String | Description | Files to Change |
| --- | --- | --- |
| `MY_EMAIL_ADDRESS` | Replace with a valid email address to satisfy the terms of service for the Let's Encrypt certificate authority used in OIDC federation. No email will actually be sent to this address. Example value: `user@example.org` | `oidc-dp-configmap.yaml` (1 appearance) |
| `MY_DISCOVERY_DOMAIN` | Replace with the domain that you will use in the A record for the OIDC Discovery Document endpoint. See [Part 2](#part-2-configure-dns-for-the-oidc-discovery-provider-ip-address) for details. Example value: `oidc-discovery.example.org` | `ingress.yaml` (2 appearances), `oidc-dp-configmap.yaml` (1 appearance), `server-configmap.yaml` (1 appearance) |
| `MY_CLUSTER_NAME` | Replace with the name of the Kubernetes cluster where SPIRE will be deployed. Example value: `gke_dev-prj_name-central1-c_vault-oidc-tutorial` | `server-configmap.yaml` (1 appearance) |

In the YAML files, instances of the `example.org` [trust domain](https://spiffe.io/spiffe/concepts/#trust-domain) are valid to use for this tutorial and do not need to be changed.

## Deploy the OIDC Discovery Provider Configmap

The SPIRE OIDC Discovery Provider provides a URL to the location of the Discovery Document specified by the OIDC protocol. The `oidc-dp-configmap.yaml` file specifies the URL to the OIDC Discovery Provider.

Before running the command below, ensure that you have replaced the `MY_DISCOVERY_DOMAIN` placeholder with the FQDN of the Discovery Provider as described in [Replace Placeholder Strings in YAML Files](#replace-placeholder-strings-in-yaml-files).

Change to the directory `k8s/oidc-vault/k8s` containing the YAML files that describe the Kubernetes deployment and use the following command to apply the updated server ConfigMap, the ConfigMap for the OIDC Discovery Provider, and deploy the updated `spire-server` StatefulSet:

```console
$ kubectl apply \
    -f server-configmap.yaml \
    -f oidc-dp-configmap.yaml \
    -f server-statefulset.yaml
```

To verify that the `spire-server` pod has `spire-server` and `spire-oidc` containers, run:

```console
$ kubectl get pods -n spire -l app=spire-server -o \
    jsonpath='{.items[*].spec.containers[*].name}{"\n"}'
```

This should output:

```console
spire-server spire-oidc
```

## Configure the OIDC Discovery Provider Service and Ingress

Use the following command to set up a Service definition for the OIDC Discovery Provider and to configure an Ingress for that Service:

```console
$ kubectl apply \
    -f server-oidc-service.yaml \
    -f ingress.yaml 
```


# Part 2: Configure DNS for the OIDC Discovery IP Address

As part of this tutorial, you will need to register a public DNS record that will resolve to the public IP address of your Kubernetes cluster. This will require you or an administrator to have registered a domain name (e.g. `example.org`) with a domain name registrar, have configured its name server to point to a DNS service, and have the ability to create a new A record for the subdomain (e.g. `oidc-discovery.example.org`) in that DNS service. If you don't have a registered domain name or access to a DNS service, services like Google Domains can help you set one up for a fee.

In this tutorial, the subdomain that you create will provide an endpoint to the Discovery Document specified by the OIDC protocol. The Vault server will query this endpoint as part of the authentication handshake between the Vault server and SPIRE.

Integration with Vault is also possible using [JWKS](https://tools.ietf.org/html/rfc7517). This method does not require a DNS entry but does require that Vault be deployed inside the Kubernetes deployment, unlike the method described in this tutorial. As such, these instructions don't describe how to integrate with Vault using the JWKS method, but you can find more information on the [Vault documentation site](https://www.vaultproject.io/api-docs/auth/jwt#jwks_url).

## Retrieve the IP Address of the SPIRE OIDC Discovery Provider

Run the following command to retrieve the external IP address of the `spire-oidc` service. The `spire-oidc` Discovery Provider service must provide an external IP address for Vault to access the OIDC Discovery document provided by `spire-oidc`.

```console
$ kubectl get service -n spire spire-oidc

NAME           TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)          AGE
spire-oidc     LoadBalancer   10.12.0.18    34.82.139.13   443:30198/TCP    108s
```

## Configure an A Record for the OIDC Discovery Document Endpoint

Using your preferred DNS tool, put the `MY_DISCOVERY_DOMAIN` domain and the `spire-oidc` external IP address in a new DNS A record. The A record should take the following form:

```console
MY_DISCOVERY_DOMAIN          A        <EXTERNAL-IP for spire-oidc service>
```

For example:
```console
oidc-discovery.example.org   A        34.82.139.13
```

Note: Do not use the `oidc-discovery.example.org` domain or IP address shown above.

## Verify the DNS A Record

As with any change to DNS, it will take minutes or hours for the new A record to propagate to DNS servers. This tutorial will not work until the A record is propagated. Negative DNS query results will be cached, causing headaches. So, to be safe, wait an hour or so to test the DNS change after creating the A record.

1. Use `nslookup` to display the DNS information for the domain you configured in the A record:

   ```console
   $ nslookup oidc-discovery.example.org
   Server:        203.0.113.0
   Address:	      203.0.113.0#53

   Non-authoritative answer:
   Name:	oidc-discovery.example.org
   Address: 93.184.216.34
   ```

   The `Address:` field at the bottom should correspond to the IP address in the A record.

2. In your browser, navigate to `https://MY_DISCOVERY_DOMAIN/.well-known/openid-configuration`. You should see JSON output similar to the following:

   ```json
   {
     "issuer": "https://oidc-discovery.example.org",
     "jwks_uri": "https://oidc-discovery.example.org/keys",
     "authorization_endpoint": "",
     "response_types_supported": [
       "id_token"
     ],
     "subject_types_supported": [],
     "id_token_signing_alg_values_supported": [
       "RS256",
       "ES256",
       "ES384"
     ]
   }
   ```


# Part 3: Install and Configure the Vault Server

After configuring an A Record for the OIDC Discovery document endpoint, continue with configuring the Vault server.

## Install Vault

Ensure that HashiCorp Vault is installed on your local computer and that the location of the `vault` executable is in your system `PATH`. Verify that Vault is installed by typing `vault version` in a terminal window. The output indicates Vault version if it is installed, or a _command not found_ error otherwise, in which case you need to install Vault. Packages are available for some Linux flavors, MacOS (via Homebrew) and Windows (via Chocolatey). Alternatively, you can [download a precompiled binary](https://www.vaultproject.io/downloads) for your operating system. For complete installation instructions, see [Install Vault](https://www.vaultproject.io/docs/install) or [Getting Started - Install Vault](https://learn.hashicorp.com/tutorials/vault/getting-started-install).
 
Use a new Vault installation for this tutorial. An existing Vault installation may have configuration settings that conflict with this tutorial. 

## Create the Config File and Run the Vault Server

First, let's review the config file we will be using for our local Vault server.

Open up a terminal window and ensure your current path is `./k8s/oidc-vault` inside of the directory where you have cloned the `spire-tutorials` repository.

In `./vault/config.hcl` we define that the Vault server will listen on our local interface 127.0.0.1 at port 8200. We'll disable TLS for simplicity (don't do this on a production environment) and set a default `file` backend:

``` console
listener "tcp" {
   address     = "127.0.0.1:8200",
   tls_disable = 1
}

storage "file" {
   path = "vault-storage"
}
```

1. Let's spin up the Vault server using our config file:

   ```console
   $ vault server -config ./vault/config.hcl
   ```

2. Check that your Vault server has started correctly and has no errors. It is typical to see some warning messages. The following message indicates that the Vault server has started:

   ```console
   ==> Vault server started! Log data will stream in below:
   ```

## Initialize and Unseal the Vault

Before authenticating and using our Vault server we need to initialize and unseal it.

1. Set the `VAULT_ADDR` environment variable. This tells the Vault CLI where it needs to talk to:

   ```console
   $ export VAULT_ADDR=http://127.0.0.1:8200
   ```

2. Initialize Vault:

   ```console
   $ vault operator init
   ```
   This outputs something like this:
   ```console
   ...
   Unseal Key 1: VI0/4yK8H/tHC625aDYaf62+Jmo5qqlizn5bVmsbY0j0
   Unseal Key 2: UINTf0oPzpiMIhOU3CNzFpo6Pkun36hGKPlcbQUkl1qT
   Unseal Key 3: SYO0yTfCn5IkoQ5f/JzE98yQI8Nfiv51gjXZMamyjXn/
   Unseal Key 4: 90vXLQJqba32VpBxYr4jB9gRVu6gRC/uWt812oF44zzP
   Unseal Key 5: 2eBBVUC63DOPqNKn4WPoxci4VOfchA7tOr3LTqHtS5FC

   Initial Root Token: s.PFuCtYgzjh6mRAfAVjfsGv3O
   ...
   ```
   Take note of the Unseal Keys and the Initial Root Token.

3. Now we need to unseal our Vault. We use 3 of our 5 Unseal Keys (whichever you want) and the Initial Root Token from the previous step.
   When we run the command we are prompted for one of our Unseal Keys.
   
   We need to repeat this process three times with three different keys:

   ```console
   $ vault operator unseal

   Unseal Key (will be hidden): <PASTE ONE OF YOUR KEYS HERE>
   
   Key                Value
   ---                -----
   Seal Type          shamir
   Initialized        true
   Sealed             true # <- this means that Vault is still sealed
   Total Shares       5
   Threshold          3
   Unseal Progress    1/3 # <- this is how many keys you have entered
   Unseal Nonce       e1bf3fa2-0058-5703-e2dc-a5c45c1b7f9a
   Version            1.3.4
   HA Enabled         false
   ```
   Note that here we see a key `Sealed` that tells us that Vault has not been unsealed yet, and a key `Unseal Progress` that says how many correct Unseal Keys we have entered.
   
   Once we entered three different correct keys we have successfully unsealed Vault and the key `Seal` changes to `false`.
   
   ```console
   Sealed          false
   ```

### Enable Secrets Engine and Store a Test Secret

Using our root access via the CLI (by storing the Initial Root Token in a `VAULT_TOKEN` environment variable) we are going to enable the `kv` (key-value) secrets engine and store a secret that we are going to retrieve later using our SPIRE-enabled login.

1. Given that you may be in a different terminal window, let's set the `VAULT_ADDR` again, and the `VAULT_TOKEN` with the Initial Root Token:

   ```console
   $ export VAULT_ADDR=http://127.0.0.1:8200
   $ export VAULT_TOKEN="s.PFuCtYgzjh6mRAfAVjfsGv3O" # <- here use the Initial Root Token from the previous section
   ```

2. Enable the `kv` (key-value) secrets engine on the `secret/` path:

   ```console
   $ vault secrets enable -path=secret kv
   ```

3. Put a secret in the new path. This is what we are going to retrieve using our SPIRE-enabled identity. Since we've specified a key-value Vault secret engine, we'll store a key-value pair in Vault:

   ```console
   $ vault kv put secret/my-super-secret test=123
   ```

### Set up Vault OIDC Federation with SPIRE

In this section, we'll configure the Vault server to federate with our SPIRE Server that is running on a Kubernetes cluster.

1. Enable the JWT authentication method:

   ```console
   $ vault auth enable jwt
   ```

2. Set up our OIDC Discovery URL, using the DNS A Record we defined in a previous section:

   ```console
   $ vault write auth/jwt/config oidc_discovery_url=https://oidc-discovery.example.org default_role=“dev”
   ```

3. Define a policy `my-dev-policy` that will be assigned to a `dev` role that we'll create in the next step.

   Ensure your current path is `./k8s/oidc-vault` inside of the directory where you have cloned the `spire-tutorials` repository.
   In [vault-policy.hcl](./vault/vault-policy.hcl) we define a policy with read capabilities for the path `/secret/my-super-secret`:

   ```console
   path "secret/my-super-secret" {
      capabilities = ["read"]
   }
   ```

   then load the policy into Vault:

   ```console
   $ vault policy write my-dev-policy ./vault/vault-policy.hcl
   ```

4. Create a role `dev`, binding the subject and audience that will be in the JWT, and configuring the `sub` claim that will be used to identify the user. Also set up a 24 hour TTL for testing purposes and a policy `my-dev-policy` that will be assigned to the tokens:

   ```console
   $ vault write auth/jwt/role/dev role_type=jwt user_claim=sub bound_audiences=TESTING bound_subject=spiffe://example.org/ns/default/sa/default token_ttl=24h token_policies=my-dev-policy
   ```

## Get Vault Credentials

Now we are going to get an access token to use with Vault. We'll use a sample client workload to get an identity using the SPIRE Federation feature.

### Get the JWT-SVID

1. First, let's get the client pod name we created in the Kubernetes Getting Started Guide:

   ```console
   $ kubectl get pods
   ```
   output:
   ```
   NAME                      READY   STATUS    RESTARTS   AGE
   client-7c94755d97-mq8dl   1/1     Running   1          10d
   ```

2. Get the JWT-SVID that identifies our client workload:

   ```console
   kubectl exec client-7c94755d97-mq8dl -- /opt/spire/bin/spire-agent api fetch jwt \
      -audience TESTING \
      -socketPath /run/spire/sockets/agent.sock
   ```

3. Copy the JWT from the response into your clipboard. You'll find the JWT under `token(spiffe://example.org/ns/default/sa/default)`. It looks something like this:

   ```console
   eyJhbGciOiJSUzI1NiIsImtpZCI6IjQ0c0R2cW9kRHRUUmVqR1pTMmZ4c2RUdTNuc3FmTzl6IiwidHlwIjoiSldUIn0.eyJhdWQiOlsiVEVTVElORyJdLCJleHAiOjE1ODgwOTIyODgsImlhdCI6MTU4ODA5MTk4OCwiaXNzIjoiaHR0cHM6Ly9zcGlyZS12YXVsdC1vaWRjLnNraXRhbGVlLm9yZyIsInN1YiI6InNwaWZmZTovL2V4YW1wbGUub3JnL25zL2RlZmF1bHQvc2EvZGVmYXVsdCJ9.Me8U9qE6yyd5mezSiMcPgwoJm2ihQZXTL-0ClAJyssg9yhCx1D4Gea3_n4pFjp86RfLiUSsGzyjBL4r0FRA6_0grJFnLdret2ynni6zZyYw6s0k38vsJIZ4rZNfY09IanQ1Ak_GW1yHVOtzRqd3vr8GgrtXzHzsWfl5YgzhWozJUYVIj1eN91aftJ-Iuvo2KYcxu1QgrIhP8Ec_6m2Kg06oRsKCb0a6C4J78wW-lXd5orDvrO2wAksmUjBwtxFA6EggtVVSKE85EG7gUgPT1xU7B2rggXC1RKUgxXqpFWHk-7qbFdk7enurxsSSGqvVSIW7KK0sYTcw5GeKze0iggQ
   ```

### Authenticate to Vault Server

1. Create a file somewhere in your home directory called `payload.json` that contains the line below. Paste your JWT from the previous step in the location indicated, omitting the angle brackets:

   ```console
   {"role": "dev","jwt": "<PASTE_YOUR_JWT_TOKEN_HERE>"}
   ```

2. Authenticate against the Vault server REST API using the payload:

   ```console
   $ curl --request POST --data @/path/to/payload.json http://localhost:8200/v1/auth/jwt/login
   ```

3. Under `auth`, grab your `client_token` from the response (for example, save it in your clipboard). This is how we are going to identify ourselves against the Vault REST API.
In the output, notice the `my-dev-policy` that we specified in Vault before. This will allow us to read our secret.
   ```json
   {
      "request_id": "78bc2546-8e3f-900e-ac32-ae590870ea67",
      "lease_id": "",
      "renewable": false,
      "lease_duration": 0,
      "data": null,
      "wrap_info": null,
      "warnings": null,
      "auth": {
         "client_token": "s.lQ3KIYjUnFwCJkUnOKKF8kxn", # <- your token
         "accessor": "ZdVaNVQDcOL15FNSjyWogwiX",
         "policies": [
               "default",
               "my-dev-policy"  # <- the role policy we created
         ],
         "token_policies": [
               "default",
               "my-dev-policy"
         ],
         "metadata": {
               "role": "dev"
         },
         "lease_duration": 86400,
         "renewable": true,
         "entity_id": "5e467f7c-7270-6e2d-2929-e76b9d2b5b32",
         "token_type": "service",
         "orphan": true
      }
   }
   ```

## Part 4: Test the Access to the Secret

Let's test our new client token and try to get the secret we created before.

1. Get the secret using our `client_token` from the previous step:

   ```console
   $ curl \
        -H "X-Vault-Token: <PASTE_YOUR_client_token_HERE>" \
        http://127.0.0.1:8200/v1/secret/my-super-secret
   ```

   The `curl` command queries the Vault server REST API using `client_token` to authenticate. The Vault server REST API returns the following JSON output, which includes the secret key-value pair that we stored in Vault earlier:
   
   ```json
   {
      "request_id": "1a10d3f7-e3b4-2c05-48c5-94a04f3758bc",
      "lease_id": "",
      "renewable": false,
      "lease_duration": 2764800,
      "data": {
         "test": "123"      # <- here's our secret key-value pair
      },
      "wrap_info": null,
      "warnings": null,
      "auth": null
   }
   ```

# Cleanup

When you are finished running this tutorial, you can use the following commands to remove the SPIRE setup for Vault OIDC Authentication.

## Kubernetes Cleanup

Keep in mind that these commands will also remove the setup that you configured in the [Kubernetes Quickstart](https://spiffe.io/spire/try/getting-started-k8s/).

1. Delete the workload container:

   ```console
   $ kubectl delete deployment client
   ```

2. Delete all deployments and configurations for the SPIRE Agent, Server, and namespace:

   ```console
   $ kubectl delete namespace spire
   ```

3. Delete the ClusterRole and ClusterRoleBinding settings:

   ```console
   $ kubectl delete clusterrole spire-server-trust-role spire-agent-cluster-role
   $ kubectl delete clusterrolebinding spire-server-trust-role-binding spire-agent-cluster-role-binding
   ```


You may also need to remove configuration elements from your cloud-based Kubernetes environment.

## Vault Cleanup

Delete the policy and JWT config that you configured for this tutorial.
```console
$ vault policy delete my-dev-policy
$ vault auth disable jwt
```

## DNS Cleanup

Remove the A record that you configured for the SPIRE OIDC Discovery document endpoint.
