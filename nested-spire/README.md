
# Overview

Nested SPIRE allows SPIRE Servers to be “chained” together, and for all servers to still issue identities in the same trust domain, meaning all Workloads identified in the same trust domain are issued identity documents that can be verified against the root keys of the trust domain.

Nested topologies works by co-locating a SPIRE Agent with every downstream SPIRE Servers being “chained”. The downstream SPIRE Server obtains credentials over the Workload API that it uses to directly authenticate with the upstream SPIRE Server to obtain an intermediate CA.

To demonstrate a deploy of SPIRE in a nested topology we create a scenario using Docker Compose with a root SPIRE deployment and two SPIRE deployment nested to it.

![Nested SPIRE diagram][nested-SPIRE-diagram]

[nested-SPIRE-diagram]: images/Nested_SPIRE_Diagram.png "Nested SPIRE Deployment diagram"

The Nested topology is well suited for multi-cloud deployments. Due to the ability to mix and match node attestors, the downstream servers can reside and provide identities for Workloads and Agents in different cloud provider environments.

In this tutorial you will learn how to:
* Configure SPIRE in a Nested topology.
* Configure the UpstreamAuthority plugin 
* Create registration entries for nested SPIRE servers
* Test that SVIDs created in a nested configuration are valid in the entire trust domain


# Prerequisites

Required files for this tutorial can be found in the `nested-spire` directory in https://github.com/spiffe/spire-tutorials. If you didn't already clone the repository please do so now.

Before proceeding, review the following:
- A 64 bit Linux or macOS environment
- Docker and Docker Compose installed
- Go 1.14.4 or higher


# Part 1: Run Services

Change to the directory `nested-spire` that contains the required files to complete the tutorial. There are three directories, one for each of the SPIRE deployment, `root`, `nestedA` and `nestedB`. These directories hold the configuration files for the SPIRE Servers and Agents. They will also contain the private keys and certificates created to attest the Agents on the Servers with the [x509pop Node Attestor](https://github.com/spiffe/spire/blob/master/doc/plugin_server_nodeattestor_x509pop.md) plugin. Private Keys and certificates are created at the initialization of the scenario using a go application which details are out of the scope of this tutorial.

## Creating a Share Directory

The first thing to do is to create a local directory that will be volume mounted on the services to share the Workload API between the root SPIRE Agent and its nested SPIRE Servers.

```console
   mkdir sharedRootSocket
```

## Configuring Root SPIRE Deployment

Configuration files for [root-server](root/server/server.conf) and [root-agent](root/agent/agent.conf) do not have any special configuration but it worth noting the location defined to bind the workload API socket by the SPIRE Agent: `socket_path ="/opt/spire/sockets/workload_api.sock"`. It will be used later to configure a volume to share the Workload API with the nested servers.

We define all the services for the tutorial at the [docker-compose.yaml](docker-compose.yaml) file. On the `root-agent` service definition we mount the `/opt/spire/sockets` directory from the SPIRE Agent container on the new local directory `sharedRootSocket`. In the next section, when defining the nested SPIRE Server services, we'll use this directory to mount the `root-agent` socket on their containers.

```console
   services:
     # Root
     root-server:
       image: gcr.io/spiffe-io/spire-server:0.10.1
       hostname: root-server
       volumes:
         - ./root/server:/opt/spire/conf/server
       command: ["-config", "/opt/spire/conf/server/server.conf"]
     root-agent:
       # Share the host pid namespace so this agent can attest the nested servers
       pid: "host"
       image: gcr.io/spiffe-io/spire-agent:0.10.1
       depends_on: ["root-server"]
       hostname: root-agent
       volumes:
         # Share root agent socket to be acceded by nestedA and nestedB servers
         - ./sharedRootSocket:/opt/spire/sockets
         - ./root/agent:/opt/spire/conf/agent
         - /var/run/:/var/run/
       command: ["-config", "/opt/spire/conf/agent/agent.conf"]
```

## Configuring NestedA SPIRE Deployment

The same set of configurations are required for the NestedB SPIRE deployment but those changes are not described in the text to avoid needless repetition.

SPIRE Server can be configured using different types of plugins. For Nested SPIRE deployments we use the UpstreamAuthority type that allows SPIRE server to integrate with existing PKI systems. For the guide we use the `spire` UpstreamAuthority plugin which uses an upstream SPIRE server in the same trust domain to obtain intermediate signing certificates for SPIRE server.

The configuration file for the [nestedA-server](./nestedA/server/server.conf) includes the spire UpstreamAuthority plugin definition with the `root-server` as its upstream SPIRE server.

```console
   UpstreamAuthority "spire" {
 	   plugin_data = {
 	       server_address      = "root-server"
 	       server_port         = 8081
 	       workload_api_socket = "/opt/spire/sockets/workload_api.sock"
 	   }
    }
```

On the other hand, the definition for the `nestedA-server` service at the [docker-compose.yaml](docker-compose.yaml) file mounts the new local directory `sharedRootSocket` as a volume. Remember from the previous section that the `root-agent` socket is mounted on that directory. That way the `nestedA-server` can access the `root-agent` workload API and fetch its SVID.

```console
   nestedA-server:
     # Share the host pid namespace so this server can be attested by the root agent
     pid: "host"
     image: gcr.io/spiffe-io/spire-server:0.10.1
     hostname: nestedA-server
     labels:
       # label to attest nestedA-server against root-agent
       - org.example.name=nestedA
     volumes:
       # Add root agent socket  
       - ./shared/rootSocket:/opt/spire/sockets
       - ./nestedA/server:/opt/spire/conf/server
     command: ["-config", "/opt/spire/conf/server/server.conf"]
```

## Creates Downstream Registration Entry

The `nestedA-server` must be registered on the `root-server` to get SVIDs. We achieve this by creating a registration entry at the root SPIRE Server for the `nestedA-server`.

```console
   docker-compose exec -T root-server \
       /opt/spire/bin/spire-server entry create \
       -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint root/agent/agent.crt.pem)" \
       -spiffeID "spiffe://example.org/nestedA" \
       -selector "docker:label:org.example.name:nestedA-server" \
       -downstream \
       -ttl 3600
```

The `-parentID` flag contains the SPIFFE ID of the `root-agent`. The SPIFFE ID of the `root-agent` is created by the [x509pop Node Attestor](https://github.com/spiffe/spire/blob/master/doc/plugin_server_nodeattestor_x509pop.md) plugin which defines the SPIFFE ID as `spiffe://<trust domain>/spire/agent/x509pop/<fingerprint>`. To make the entry clear to the reader, it is expressed as `fingerprint root/agent/agent.crt.pem` indicating that it contains the fingerprint of the agent certificate.
The other point to highlight is the `-downstream` option. This option when set, indicates that the entry describes a downstream SPIRE server.

## Run the Scenario

Use the `set-env.sh` script to run all the services that compound the scenario. All the configurations described in the previous sections are illustrated in the different services.
Ensure that the current working directory is `.../spire-tutorials/nested-spire` and run:

```console
    bash scripts/set-env.sh
```

Once the script is completed, in another terminal run the following command to review the logs from all the services

```console
    docker-compose logs -f -t
```


# Part 2: Test the Deployments

Now that the SPIRE deployments are ready, let's test the scenario that we've configured.

## Create Workload Registration Entries

To test the scenario we create two workload registration entries, one entry per each of the nested SPIRE deployment. The goal of the test case is to demonstrate that SVIDs created in a nested configuration are valid in the entire trust domain, not only in the scope of the server that originated the SVID.

```console
   # Workload for nestedA deployment
   docker-compose exec -T nestedA-server \
       /opt/spire/bin/spire-server entry create \
       -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint nestedA/agent/agent.crt.pem)" \
       -spiffeID "spiffe://example.org/nestedA/workload" \
       -selector "unix:uid:1001" \
       -ttl 0

   # Workload for nestedB deployment
   docker-compose exec -T nestedB-server \
       /opt/spire/bin/spire-server entry create \
       -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint nestedB/agent/agent.crt.pem)" \
       -spiffeID "spiffe://example.org/nestedB/workload" \
       -selector "unix:uid:1001" \
       -ttl 0
```

The examples uses the `$(fingerprint nestedA/agent/agent.crt.pem)` notation again to show that the `-parentID` flag is set to the SPIFFE ID of the nested SPIRE Agent. TTL equals to zero indicates that the default value of 3600 seconds will be used. Finally, in both cases there is an unix selector to identify any process that is run by the user with id 1001.
Use the following Bash script to create the registration entries:

```console
   bash scripts/create-workload-registration-entries.sh
```

## Run the Test

Once both workload registration entries are propagated, let's test that SVIDs created in a nested configuration are valid in the entire trust domain, not only in the scope of the server that originated the SVID.

The test consists on getting a JWT-SVID from the `nestedA-agent` and validate it using the `nestedB-agent`. In both cases, Docker Compose run the processes using the user 1001 to match the workload registration entries created in the previous section.

```console
    # Fetch JWT-SVID and extract token
    token=$(docker-compose exec -u 1001 -T nestedA-agent \
      /opt/spire/bin/spire-agent api fetch jwt -audience nested-test -socketPath /opt/spire/sockets/workload_api.sock | sed -n '2p')

    # Validate token
    docker-compose exec -u 1001 -T nestedB-agent \
        /opt/spire/bin/spire-agent api validate jwt -audience nested-test  -svid "${token}" \
          -socketPath /opt/spire/sockets/workload_api.sock
```

The result indicates that the JWT-SVID is valid and shows the SPIFFE ID associated to the JWT-SVID which belongs to the workload registered on the `nestedA-agent`. 

```console
    SVID is valid.
    SPIFFE ID : spiffe://example.org/nestedA/workload
    Claims    : {"aud":["nested-test"],"exp":1595814190,"iat":1595813890,"sub":"spiffe://example.org/nestedA/workload"}
```

In SPIRE this is accomplished by propagating every JWT-SVID public signing key to the whole topology. In the case of X509-SVID, this is easily achieved because of the chaining semantics that X.509 has.


# Cleanup

When you are finished running this tutorial, you can use the following command to stop all the containers

```console
   docker-compose down
```
