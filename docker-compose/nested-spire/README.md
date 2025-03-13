
# Overview

Nested SPIRE allows SPIRE Servers to be “chained” together, and for all SPIRE Servers to issue identities in the same trust domain, meaning all workloads identified in the same trust domain are issued identity documents that can be verified against the root keys of the trust domain.

Nested topologies work by co-locating a SPIRE Agent with every downstream SPIRE Server being “chained”. The downstream SPIRE Server obtains credentials over the Workload API that it uses to directly authenticate with the upstream SPIRE Server to obtain an intermediate CA.

To demonstrate a deployment of SPIRE in a nested topology we create a scenario using Docker Compose with a root SPIRE deployment and two SPIRE deployments nested to it.

![Nested SPIRE diagram][nested-SPIRE-diagram]

[nested-SPIRE-diagram]: images/Nested_SPIRE_Diagram.png "Nested SPIRE Deployment diagram"

The nested topology is well suited for multi-cloud deployments. Due to the ability to mix and match node attestors, the downstream SPIRE Servers can reside and provide identities for workloads and SPIRE Agents in different cloud provider environments.

In this tutorial you will learn how to:
* Configure SPIRE in a nested topology
* Configure the UpstreamAuthority plugin 
* Create registration entries for nested SPIRE Servers
* Test that SVIDs created in a nested configuration are valid in the entire trust domain


# Prerequisites

Required files for this tutorial can be found in the `docker-compose/nested-spire` directory in https://github.com/spiffe/spire-tutorials. If you didn't already clone the repository please do so now.

Before proceeding, review the following system requirements:
- A 64-bit Linux or macOS environment
- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/) installed (Docker Compose is included in macOS Docker Desktop)
- [Go](https://golang.org/dl/) 1.14.4 or higher installed


# Part 1: Run Services

This tutorial's `nested-spire` main directory contains three subdirectories, one for each of the SPIRE deployments: `root`, `nestedA` and `nestedB`. These directories hold the configuration files for the SPIRE Servers and Agents. They will also contain the private keys and certificates created to attest the Agents on the Servers with the [x509pop Node Attestor](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_x509pop.md) plugin. Private keys and certificates are created at the initialization of the scenario using a Go application, the details of which are out of the scope of this tutorial.

## The Shared Socket Directory

We use a shared directory that will be volume mounted on the services to share the Workload API between the root SPIRE Agent and its nested SPIRE Servers. This tutorial uses a named volume in its docker-compose configuration to share the Workload API socket.

## Configuring Root SPIRE Deployment

Configuration files for [root-server](root/server/server.conf) and [root-agent](root/agent/agent.conf) have not been changed from the default `server.conf` and `agent.conf` files, but it's worth noting the location defined to bind the workload API socket by the SPIRE Agent: `socket_path ="/opt/spire/sockets/workload_api.sock"`. This path will be used later to configure a volume to share the Workload API with the nested SPIRE Servers.

We define all the services for the tutorial in the [docker-compose.yaml](docker-compose.yaml) file. In the `root-agent` service definition we mount the `/opt/spire/sockets` directory from the SPIRE Agent container on the named `spire-sockets` volume. In the next section, when defining the nested SPIRE Server services, we'll use this directory to mount the `root-agent` socket on the SPIRE Server containers.

```console
   services:
     # Root
     root-server:
       image: ghcr.io/spiffe/spire-server:1.11.2
       hostname: root-server
       volumes:
         - ./root/server:/opt/spire/conf/server
       command: ["-config", "/opt/spire/conf/server/server.conf"]
     root-agent:
       # Share the host pid namespace so this agent can attest the nested servers
       pid: "host"
       image: ghcr.io/spiffe/spire-agent:1.11.2
       depends_on: ["root-server"]
       hostname: root-agent
       volumes:
         # Share root agent socket to be accessed by nestedA and nestedB servers
         - spire-sockets:/opt/spire/sockets
         - ./root/agent:/opt/spire/conf/agent
         - /var/run/:/var/run/
       command: ["-config", "/opt/spire/conf/agent/agent.conf"]
```

## Configuring NestedA SPIRE Deployment

The same set of configurations are required for the `nestedB` SPIRE deployment but those changes are not described in the text to avoid needless repetition.

SPIRE Agent and Server can be extended with a variety of [plugins](https://spiffe.io/spire/docs/extending/). The [UpstreamAuthority plugin](https://github.com/spiffe/spire/blob/main/doc/spire_server.md#built-in-plugins) type allows SPIRE Server to integrate with existing PKI systems. UpstreamAuthority plugins can sign certificates using CAs loaded from disk, third-party tools from AWS and Vault, and so on. Nested SPIRE deployments require the use of the [spire UpstreamAuthority plugin](https://github.com/spiffe/spire/blob/main/doc/plugin_server_upstreamauthority_spire.md) which uses an upstream SPIRE Server in the same trust domain to obtain intermediate signing certificates for SPIRE Server.

The configuration file for the [nestedA-server](./nestedA/server/server.conf) includes the `spire` UpstreamAuthority plugin definition with the `root-server` as its upstream SPIRE Server.

```console
   UpstreamAuthority "spire" {
 	   plugin_data = {
 	       server_address      = "root-server"
 	       server_port         = 8081
 	       workload_api_socket = "/opt/spire/sockets/workload_api.sock"
 	   }
    }
```

The Docker Compose definition for the `nestedA-server` service in the [docker-compose.yaml](docker-compose.yaml) file mounts the `spire-sockets` named volume. Remember from the previous section that the `root-agent` socket is mounted on that directory. That way the `nestedA-server` can access the `root-agent` workload API and fetch its SVID.

```console
   nestedA-server:
     # Share the host pid namespace so this server can be attested by the root agent
     pid: "host"
     image: ghcr.io/spiffe/spire-server:1.5.1
     hostname: nestedA-server
     labels:
       # label to attest nestedA-server against root-agent
       - org.example.name=nestedA
     volumes:
       # Add root agent socket
       - spire-sockets:/opt/spire/sockets
       - ./nestedA/server:/opt/spire/conf/server
     command: ["-config", "/opt/spire/conf/server/server.conf"]
```

## Create Downstream Registration Entry

The `nestedA-server` must be registered on the `root-server` to obtain its identity which will be used to mint SVIDs. We achieve this by creating a registration entry in the root SPIRE Server for the `nestedA-server`.

```console
   docker-compose exec -T root-server \
       /opt/spire/bin/spire-server entry create \
       -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint root/agent/agent.crt.pem)" \
       -spiffeID "spiffe://example.org/nestedA" \
       -selector "docker:label:org.example.name:nestedA-server" \
       -downstream
```

The `-parentID` flag contains the SPIFFE ID of the `root-agent`. The SPIFFE ID of the `root-agent` is created by the [x509pop Node Attestor](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_x509pop.md) plugin which defines the SPIFFE ID as `spiffe://<trust domain>/spire/agent/x509pop/<fingerprint>`. A `fingerprint()` function in the shell script calculates the SHA1 fingerprint of the certificate.
The other point to highlight is the `-downstream` option. This option, when set, indicates that the entry describes a downstream SPIRE Server.

## Run the Scenario

Use the `set-env.sh` script to run all the services that make up the scenario. The script starts the `root`, `nestedA`, and `nestedB` services with the configuration options described earlier.

Ensure that the current working directory is `.../spire-tutorials/docker-compose/nested-spire` and run:

```console
    bash scripts/set-env.sh
```

Once the script is completed, in another terminal run the following command to review the logs from all the services:

```console
    docker-compose logs -f -t
```


# Part 2: Test the Deployments

Now that the SPIRE deployments are ready, let's test the scenario that we've configured.

## Create Workload Registration Entries

To test the scenario we create two workload registration entries, one entry for each nested SPIRE Server (`nestedA` and `nestedB`). The goal of the test is to demonstrate that SVIDs created in a nested configuration are valid in the entire trust domain, not only in the scope of the SPIRE Server that originated the SVID. The following commands demonstrate the command line options we'll use to create the two workload registration entries, but you can run these commands using the `create-workload-registration-entries.sh` script shown a few lines below.

```console
   # Workload for nestedA deployment
   docker-compose exec -T nestedA-server \
       /opt/spire/bin/spire-server entry create \
       -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint nestedA/agent/agent.crt.pem)" \
       -spiffeID "spiffe://example.org/nestedA/workload" \
       -selector "unix:uid:1001" \

   # Workload for nestedB deployment
   docker-compose exec -T nestedB-server \
       /opt/spire/bin/spire-server entry create \
       -parentID "spiffe://example.org/spire/agent/x509pop/$(fingerprint nestedB/agent/agent.crt.pem)" \
       -spiffeID "spiffe://example.org/nestedB/workload" \
       -selector "unix:uid:1001"
```

The examples use the `fingerprint path/to/nested-agent-cert` form again to show that the `-parentID` flag specifies the SPIFFE ID of the nested SPIRE Agent. Finally, in both cases the unix selector assigns the SPIFFE ID to any process with a uid of 1001.

Use the following Bash script to create the registration entries using the options just described:

```console
   bash scripts/create-workload-registration-entries.sh
```

## Run the Test

Once both workload registration entries are propagated, let's test that SVIDs created in a nested configuration are valid in the entire trust domain, not only in the scope of the SPIRE Server that originated the SVID.

The test consists of getting a JWT-SVID from the `nestedA-agent` SPIRE Agent and validating it using the `nestedB-agent`. In both cases, Docker Compose runs the processes using the uid 1001 to match the workload registration entries created in the previous section.

Type this command to fetch the JWT-SVID on the `nestedA` SPIRE Agent and extract the token from the JWT-SVID:

```console
    token=$(docker-compose exec -u 1001 -T nestedA-agent \
      /opt/spire/bin/spire-agent api fetch jwt -audience nested-test -socketPath /opt/spire/sockets/workload_api.sock | sed -n '2p')
```

Run the following command to validate the token from `nestedA` on the `nestedB` SPIRE Agent:

```console
    docker-compose exec -u 1001 -T nestedB-agent \
        /opt/spire/bin/spire-agent api validate jwt -audience nested-test  -svid "${token}" \
          -socketPath /opt/spire/sockets/workload_api.sock
```

The `nestedB` SPIRE Agent outputs the following:

```console
    SVID is valid.
    SPIFFE ID : spiffe://example.org/nestedA/workload
    Claims    : {"aud":["nested-test"],"exp":1595814190,"iat":1595813890,"sub":"spiffe://example.org/nestedA/workload"}
```

The output indicates that the JWT-SVID is valid. Also, although the SPIFFE ID is registered on `nestedA` rather than `nestedB`, the SPIFFE ID is still valid on the `nestedB` SPIRE Agent because the SPIRE Agents are in the same trust domain in the nested SPIRE topology.

In SPIRE this is accomplished by propagating every JWT-SVID public signing key to the whole topology. In the case of X509-SVID, this is easily achieved because of the chaining semantics that X.509 has.


# Cleanup

When you are finished running this tutorial, you can use the following Bash script to stop all the containers:

```console
    bash scripts/clean-env.sh
```
