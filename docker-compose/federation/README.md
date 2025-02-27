
# Using SPIFFE Federation to Authenticate Workloads from Different SPIRE Servers

This tutorial shows how to authenticate two SPIFFE-identified workloads that are identified by two different SPIRE Servers.

The first part of this document demonstrates how to configure SPIFFE federation by showing the SPIRE configuration file changes and `spire-server` commands used to set up a stock quote webapp frontend and service backend. The second part of this document lists the steps you run to show the scenario in action using the Docker Compose files included in this tutorial's directory.

In this tutorial you will learn how to:

* Configure each SPIRE Server to expose its SPIFFE Federation bundle endpoint using SPIFFE authentication and Web PKI authentication.
* Configure the SPIRE Servers to retrieve trust bundles from each other.
* Bootstrap federation between two SPIRE Servers using different trust domains.
* Create registration entries for the workloads so that they can federate with other trust domain.

# Prerequisites

The baseline components for SPIFFE federation are:

* Two SPIRE Server instances running version 1.11.2.
* Two SPIRE Agents running version 1.11.2. One connected to one SPIRE Server, and the second connected to the other SPIRE Server.
* Two workloads that need to communicate each other via mTLS, and use the Workload API to get SVIDs and trust bundles.

# Scenario

Let's say we have a stock broker's webapp that wants to display stock quotes fetched from a stock market web service provider. The scenario goes as follows:  

1. The user enters the broker's webapp stock quotes URL in a browser.
2. The webapp workload receives the request and makes an HTTP request for quotes to the stock market service using mTLS.
3. The stock market service receives the request and sends the quotes in the response.
4. The webapp renders the stock quotes page using the returned quotes and sends it to the browser.
5. The browser displays the quotes to the user. The webapp includes some JavaScript to refresh the page every 1 second, so every second these steps are executed again.

In addition to the above and for the rest of this tutorial, we are going to assume the following [trust domain](https://spiffe.io/docs/latest/spiffe/concepts/#trust-domain) names for these sample SPIRE installations: `broker.example` and `stockmarket.example`. Keep in mind that trust domains do not need to correspond to actual DNS domain names. Also, the applications access the WorkloadAPI directly to get SVIDs and trust bundles, meaning there are no proxies in the scenario described.

# Configure SPIFFE Federation Endpoints

To make federation work, and because the webapp and the quotes service are going to use `mTLS`, both SPIRE Servers need each other's trust bundle. This is done, in part, by configuring a so-called federation endpoint on each SPIRE Server, which provides the API used by SPIRE Servers in other trust domains to get the trust bundle for the trust domain they want to federate with.

The federation endpoint exposed by a SPIRE Server can be configured to use one of two authentication methods: SPIFFE auth or Web PKI auth.

## Configure a Federation Endpoint Using SPIFFE Authentication

To configure the broker's SPIRE Server bundle endpoint, we use the `federation` section in the broker's SPIRE Server configuration file, by default `server.conf`:

```hcl
server {
    .
    .
    trust_domain = "broker.example"
    .
    .

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 8443
        }
    }
}
```
This will publish the federation endpoint in any IP address at port 8443 in the host where the SPIRE Server is running.

On the other side, the stock market service provider's SPIRE Server is configured in a similar fashion:
```hcl
server {
    .
    .
    trust_domain = "stockmarket.example"
    .
    .

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 8443
        }
    }
}
```

At this point, both SPIRE Servers have exposed their federation endpoints to provide their trust bundles, but none of them knows how to reach each other's federation endpoint. 

## Configure a Federation Endpoint Using Web PKI Authentication

We are going to assume that only the broker's SPIRE Server will use Web PKI authentication for its federation endpoint. The stock market SPIRE Server will still use SPIFFE Authentication. Hence, the stock market SPIRE Server configuration remains the same as seen in the previous section.

Then, to configure the broker's SPIRE Server bundle endpoint, we configure the `federation` section as follows:

```hcl
server {
    .
    .
    trust_domain = "broker.example"
    .
    .

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 443
            acme {
                domain_name = "broker.example"
                email = "some@email.com"
                tos_accepted = true
            }   
        }
    }
}
```
This will publish the federation endpoint in any IP address at port 443. We use port 443 because we're demonstrating the use of Let's Encrypt as our ACME provider (this is used by default, if you want to use a different one then you must set the `directory_url` configurable). Note that `tos_accepted` was set to `true`, meaning that we accept the terms of service of our ACME provider, which in turn is needed when using Let's Encrypt.

For SPIFFE Federation using Web PKI to work, you must own the DNS domain specified for `domain_name` (`broker.example` in our example) and the domain must resolve to the SPIRE Server exposing the federation bundle endpoint.

# Configure SPIRE Servers to Retrieve Trust Bundles From Each Other

After configuring federation endpoints, the next step to enable SPIFFE federation is to configure the SPIRE Servers to find the trust bundles for other trust domains. The `federates_with` configuration option in `server.conf` is where you specify the endpoint of the other trust domain. The configuration of this section has some slight differences when using the different methods of authentication, according with the requirements for each endpoint profile.

## Configure Trust Bundle Location Using SPIFFE Authentication (https_spiffe)

As we saw previously, the SPIRE Server of the stock market service provider has its federation endpoint listening on port `8443` at any IP address. We will also assume that `spire-server-stock` is a DNS name that resolves to the stock market service's SPIRE Server IP address. (The Docker Compose demo here uses the hostname `spire-server-stock`, but in typical usage you would specify a FQDN.) Then, the broker's SPIRE Server must be configured with the following `federates_with` section:
```hcl
server {
    .
    .
    trust_domain = "broker.example"
    .
    .

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 8443
        }
        federates_with "stockmarket.example" {
            bundle_endpoint_url = "https://spire-server-stock:8443"
            bundle_endpoint_profile "https_spiffe" {
                endpoint_spiffe_id = "spiffe://stockmarket.example/spire/server"
            }
        }
    }
}
```
Now the broker's SPIRE Server knows where to find a trust bundle that can be used to validate SVIDs containing identities from the `stockmarket.example` trust domain.

On the other side, the stock market service provider's SPIRE Server must be configured in a similar fashion:
```hcl
server {
    .
    .
    trust_domain = "stockmarket.example"
    .
    .

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 8443
        }
        federates_with "broker.example" {
            bundle_endpoint_url = "https://spire-server-broker:8443"
            bundle_endpoint_profile "https_spiffe" {
                endpoint_spiffe_id = "spiffe://broker.example/spire/server"
            }
        }
    }
}
```
Note that the "https_spiffe" profile has been specified, indicating the expected SPIFFE ID of the bundle endpoint. Specifying the `federation` section and `federates_with` subsection of `server.conf` is all that's needed to configure SPIFFE federation. To finish enabling SPIFFE federation, we need to bootstrap the trust bundles and register the workloads using `spire-server` commands as described below.

## Configure Trust Bundle Location Using Web PKI authentication (https_web)

As mentioned, in this alternate scenario we are assuming that only the broker's SPIRE Server will use Web PKI authentication for its federation endpoint, so the `federates_with` configuration for the broker server is the same as seen in the previous section. However, the SPIRE Server of the stock market service provider needs a different configuration that specifies the "https_web" profile instead of "https_spiffe":

```hcl
server {
    .
    .
    trust_domain = "stockmarket.example"
    .
    .

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 8443
        }
        federates_with "broker.example" {
            bundle_endpoint_url = "https://spire-server-broker:8443"
            bundle_endpoint_profile "https_web" {}
        }
    }
}
```
It can be noticed that the "https_web" profile does not require additional configuration settings. Endpoints are authenticated using the same public CA certificates installed in the operating system.

# Bootstrap Federation

We have configured the SPIRE Servers with the address of the federation endpoints, but this is not enough to make federation work. To enable the SPIRE Servers to fetch the trust bundles from each other they need each other's trust bundle first, because they have to authenticate the SPIFFE identity of the federated server that is trying to access the federation endpoint. Once federation is bootstrapped, the trust bundle updates are fetched trough the federation endpoint API using the current trust bundle.

The bootstrapping is done using a couple of SPIRE Server commands: `bundle show` and `bundle set`.

## Get the Bootstrap Trust Bundle

Let's say we want to get the broker's SPIRE Server trust bundle. On the node where the broker's SPIRE Server is running we run:

```
broker> spire-server bundle show -format spiffe > broker.example.bundle
```

This saves the trust bundle in the `broker.example.bundle` file. Then the broker must give a copy of this file to the stock market service folks, so they can store this trust bundle on their SPIRE Server and associate it with the `broker.example` trust domain. To achieve this, the stock market service folks must run the following on the node where they have SPIRE Server running:

```
stock-market> spire-server bundle set -format spiffe -id spiffe://broker.example -path /some/path/broker.example.bundle
```

At this point the stock market service's SPIRE Server is able to validate SVIDs having SPIFFE IDs with a `broker.example` trust domain. However, the broker's SPIRE Server is not yet able to validate SVIDs having SPIFFE IDs with a `stockmarket.example` trust domain. To make this possible, the stock market folks must run the following on the node where they have SPIRE Server running:

```
stock-market> spire-server bundle show -format spiffe > stockmarket.example.bundle
```

Then the stock market folks must give a copy of this file to the broker folks, so they can store this trust bundle on their SPIRE Server and associate it with the `stockmarket.example` trust domain. To achieve this, the broker folks must run the following on the node where they have SPIRE Server running:

```
broker> spire-server bundle set -format spiffe -id spiffe://stockmarket.example -path /some/path/stockmarket.example.bundle
```

Now both SPIRE Servers can validate SVIDs having SPIFFE IDs with each other's trust domain, thus both can start fetching trust bundle updates from each other's federation endpoints. Also, as of now they can create registration entries for federating as shown in the next section.

Note that the creation of the `broker.example.bundle` file (and later importing by the stock market service) is not needed when the broker's SPIRE Server is using Web PKI authentication for its federation bundle endpoint.

# Create Registration Entries for Federation

Now that the SPIRE Servers have each other's trust bundle, let's see how they can create registration entries to federate with each other.

To simplify things, we are going to suppose that the stock market webapp and the quotes service are both running on Linux boxes, one owned by the stock market organization and the other owned by the broker. Since they are using SPIRE, each Linux box also has a SPIRE Agent installed. In addition to this, the webapp is run using the `webapp` user, and the quotes service is run using the `quotes-service` user.

With those assumptions, in the SPIRE Server node of the broker, the broker folks must create a registration entry. The `-federatesWith` flag is required to enable SPIFFE federation:

```
broker> spire-server entry create \
	-parentID <SPIRE Agent's SPIFFE ID> \
	-spiffeID spiffe://broker.example/webapp \
	-selector unix:user:webapp \
	-federatesWith "spiffe://stockmarket.example"
```

By specifying the `-federatesWith` flag, once this registration entry is created, when the webapp's SPIRE Server asks for an SVID it will get one from the broker's SPIRE Server with the `spiffe://broker.example/webapp` identity, along with the trust bundle associated to the `stockmarket.example` trust domain.

On the stock market service side, they must create a registration entry as follows:

```
stock-market> spire-server entry create \
	-parentID <SPIRE Agent's SPIFFE ID> \
	-spiffeID spiffe://stockmarket.example/quotes-service \
	-selector unix:user:quotes-service \
	-federatesWith "spiffe://broker.example"
```

Similarly, once this registration entry is created, when the quotes service asks for an SVID it will get one having the `spiffe://stockmarket.example/quotes-service` identity, along with the trust bundle associated to the `broker.example` trust domain.

That is about it. Now all the pieces are in place to make federation work and demonstrate how the webapp is able to communicate with the quotes service despite having identities with different trust domains.

# Federation Example Using SPIFFE Authentication

This section explains how to use Docker Compose to try an example implementation of the SPIFFE auth scenario described in this tutorial.

Although not shown here, you could make the changes shown in the Web PKI authentication sections to try the Web PKI scenario. Remember that to configure Web PKI, the FQDN specified for `domain_name` must be owned by you and resolvable over the internet via DNS.

## Requirements

Required files for this tutorial can be found in the `docker-compose/federation` directory in https://github.com/spiffe/spire-tutorials. If you didn't already clone the repository please do so now.

Before proceeding, review the following system requirements:
- A 64-bit Linux or macOS environment
- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/) installed (Docker Compose is included in macOS Docker Desktop)
- [Go](https://golang.org/dl/) 1.14.4 or higher installed

## Build

Ensure that the current working directory is `.../spire-tutorials/docker-compose/federation` and run the following command to create the files needed for Docker Compose:

```
$ ./build.sh
```

## Run

Run the following command to start the SPIRE Servers and the applications:

```
$ docker compose up -d
```

## Start SPIRE Agents 

Run the following command to start the SPIRE Agents:

```
$ ./1-start-spire-agents.sh
```

## Bootstrap Federation

Run the following command to [bootstrap the federation](#bootstrap-federation):

```
$ ./2-bootstrap-federation.sh
```

## Create Workload Registration Entries

Run the following command to create [workload registration entries](#create-registration-entries-for-federation):

```
$ ./3-create-registration-entries.sh
```

After running this script, it may take some seconds for the applications to receive their SVIDs and trust bundles. 

## See the Scenario Working In a Browser

Open up a browser to http://localhost:8080/quotes and you should see a grid of randomly generated phony stock quotes that are updated every 1 second.

## See the Configuration

To see the broker's SPIRE Server configuration you can run:

```
$ docker compose exec spire-server-broker cat conf/server/server.conf
```

You should see:

```
server {
    bind_address = "0.0.0.0"
    bind_port = "8081"
    socket_path = "/tmp/spire-server/private/api.sock"
    trust_domain = "broker.example"
    data_dir = "/opt/spire/data/server"
    log_level = "DEBUG"
    log_file = "/opt/spire/server.log"
    default_svid_ttl = "1h"
    ca_subject = {
        country = ["US"],
        organization = ["SPIFFE"],
        common_name = "",
    }

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 8443
        }
        federates_with "stockmarket.example" {
            bundle_endpoint_url = "https://spire-server-stock:8443"
            bundle_endpoint_profile "https_spiffe" {
                endpoint_spiffe_id = "spiffe://stockmarket.example/spire/server"
            }
        }
    }
}

plugins {
    DataStore "sql" {
        plugin_data {
            database_type = "sqlite3"
            connection_string = "/opt/spire/data/server/datastore.sqlite3"
        }
    }

	NodeAttestor "x509pop" {
		plugin_data {
			ca_bundle_path = "/opt/spire/conf/server/agent-cacert.pem"
		}
	}

    KeyManager "memory" {
        plugin_data = {}
    }
}
```

To see the stock market's SPIRE Server configuration you can run:

```
$ docker compose exec spire-server-stock cat conf/server/server.conf
```

You should see:

```
server {
    bind_address = "0.0.0.0"
    bind_port = "8081"
    socket_path = "/tmp/spire-server/private/api.sock"
    trust_domain = "stockmarket.example"
    data_dir = "/opt/spire/data/server"
    log_level = "DEBUG"
    log_file = "/opt/spire/server.log"
    default_svid_ttl = "1h"
    ca_subject = {
        country = ["US"],
        organization = ["SPIFFE"],
        common_name = "",
    }

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 8443
        }
        federates_with "broker.example" {
            bundle_endpoint_url = "https://spire-server-broker:8443"
            bundle_endpoint_profile "https_spiffe" {
                endpoint_spiffe_id = "spiffe://broker.example/spire/server"
            }
        }
    }
}

plugins {
    DataStore "sql" {
        plugin_data {
            database_type = "sqlite3"
            connection_string = "/opt/spire/data/server/datastore.sqlite3"
        }
    }

	NodeAttestor "x509pop" {
		plugin_data {
			ca_bundle_path = "/opt/spire/conf/server/agent-cacert.pem"
		}
	}

    KeyManager "memory" {
        plugin_data = {}
    }
}
```

## See the Registration Entries

To see the broker's SPIRE Server registration entries you can run:

```
$ docker compose exec spire-server-broker bin/spire-server entry show
```

You should see something like this:

```
Found 1 entry
Entry ID      : 2d799235-ddca-4088-ba6f-bf54d2af918f
SPIFFE ID     : spiffe://broker.example/webapp
Parent ID     : spiffe://broker.example/spire/agent/x509pop/4f9238aaa7a93cf96ca3d6060abe27bc51a267e7
Revision      : 0
TTL           : 3600
Selector      : unix:user:root
FederatesWith : spiffe://stockmarket.example
```

To see the stock martket's SPIRE Server registration entries you can run:

```
$ docker compose exec spire-server-stock bin/spire-server entry show
```

You should see something like this:

```
Found 1 entry
Entry ID      : e42e8d6b-0a0a-4e38-b544-08510c35cbbe
SPIFFE ID     : spiffe://stockmarket.example/quotes-service
Parent ID     : spiffe://stockmarket.example/spire/agent/x509pop/50686366996ece3ca8e528765af685fe81f81435
Revision      : 0
TTL           : 3600
Selector      : unix:user:root
FederatesWith : spiffe://broker.example
```

## Cleanup

```
$ docker compose down
```
