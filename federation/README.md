
# Overview

This tutorial shows how to authenticate two SPIFFE-identified workloads that are identified by two different SPIRE Servers.

In this tutorial you will learn how to:

* Configure each SPIRE Server to expose it's SPIFFE Federation bundle endpoint using SPIFFE authentication.
* Configure the SPIRE Servers to retrieve trust bundles from each other (using the federate_with configuration section).
* Bootstrap federation between two SPIRE Servers using different trust domains.
* Create registration entries for the workloads so that they can federate with other trust domain.

# Prerequisites

* Two SPIRE Servers instances.
* Two SPIRE Agents, one connected to one SPIRE Server, and the second connected to the other SPIRE Server.
* Two workloads that needs to communicate each other via mTLS, and use the Workload API to get SVIDs and trust bundles.

# Scenario

Let's say we have a stock broker's webapp that wants to display stock quotes fetched from a stocks market webservice provider. The scenario goes as follows:  

1. The user enters the broker's webapp stock quotes URL in a browser.
2. The webapp workload receives the request and makes an HTTP request for quotes to the stocks market service using mTLS.
3. The stocks market service receives the request and sends the quotes in the response.
4. The webapp renders the stock quotes page using the returned quotes and sends it to the browser.
5. The browser displays the quotes to the user. The webapp includes some javascript to refresh the page every 1 second, so every second these steps are executed again.

In addition to the above and for the rest of this tutorial, we are going to assume the following trust domain names for their SPIRE installations: `broker.org` and `stocksmarket.org`.  
Also, the applications access the WorkloadAPI directly to get SVIDs and trust bundles, meaning there are no proxies in the scenario described.

# Configuring SPIFFE Federation endpoint

To make federation work, and because the webapp and the quotes service are going to use `mTLS`, both SPIRE Servers need the trust bundle of each other. This is done (in part) by configuring the so called federation endpoint, which provides the API used by SPIRE Servers in other trust domains to get the trust bundle for the trust domain they want to federate with.

The federation endpoint exposed by a SPIRE Server can be configured to use one of two authentication methods: SPIFFE auth or WebPKI auth.

## Using SPIFFE authentication

To configure the broker's SPIRE Server bundle endpoint, we use the `federation` section in the broker's SPIRE Server configuration file:

```hcl
server {
    .
    .
    trust_domain = "broker.org"
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

On the other side, the stocks market service provider's SPIRE Server is configured in a similar fashion:
```hcl
server {
    .
    .
    trust_domain = "stocksmarket.org"
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

At this point, both SPIRE Servers expose their federation endpoints to provide their trust bundles, but none of them knows how to reach each other's federation endpoint. 

# Configure the SPIRE Servers to retrieve trust bundles from each other

This is the other part of the SPIRE Server configuration needed in order to achieve federation, we need to tell each SPIRE Server where it can find the trust bundles for other trust domains, in other words, we have to configure the `federate_with` section. The configuration of this section has some slight differences when using the different methods of authentication.

## Using SPIFFE authentication

As we saw previously, the SPIRE Server of the stocks market service provider have its federation endpoint listening on port `8443` at any IP. We will also assume that `spire-server-stocks` is a DNS name that resolves to the stocks market service's SPIRE Server IP. Then, the broker's SPIRE Server must be configured with the following `federate_with` section:
```hcl
server {
    .
    .
    trust_domain = "broker.org"
    .
    .

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 8443
        }
        federates_with "stocksmarket.org" {
            bundle_endpoint {
                address = "spire-server-stocks"
                port = 8443
            }
        }
    }
}
```
Now the broker's SPIRE Server knows where to find a trust bundle that can be used to validate SVIDs containing identities from `stocksmarket.org` trust domain.

On the other side, the stocks market service provider's SPIRE Server must be configured in a similar fashion:
```hcl
server {
    .
    .
    trust_domain = "stocksmarket.org"
    .
    .

    federation {
        bundle_endpoint {
            address = "0.0.0.0"
            port = 8443
        }
        federates_with "broker.org" {
            bundle_endpoint {
                address = "spire-server-broker"
                port = 8443
            }
        }
    }
}
```
That is it, that is all we need about SPIRE Server configuration.

# Bootstrap federation

We have configured the SPIRE Servers with the address of the federation endpoints, but this is not enough to make federation work. To enable the SPIRE Servers to fetch the trust bundles from each other they need each other's trust bundle first, because they have to authenticate the SPIFFE identity of the federated server that is trying to access the federation endpoint. Once federation is bootstrapped the trust bundle updates are fetched troughth the federation endpoint API using the current trust bundle.

This is done using a couple of SPIRE Server commands: `experimental bundle show` and `experimental bundle set`.

## Getting the bootstrap trust bundle

Let's say we want to get the broker's SPIRE Server trust bundle, on the node where the SPIRE Server is running we run:

```
broker> spire-server experimental bundle show > broker.org.bundle
```

This would save the trust bundle in the `broker.og.bundle` file. Then the broker must give a copy of this file to the stocks market service folks, so they can store this trust bundle on their SPIRE Server and associate it with the `broker.org` trust domain. To achieve this, the stocks market service folks must run the following on the node where they have SPIRE Server running:

```
stocks-market> spire-server experimental bundle set -id spiffe://broker.org -path /some/path/broker.org.bundle
```

At this point the stocks market service's SPIRE Server is able to validate SVIDs having SPIFFE IDs with a `broker.org` trust domain. However, the broker's SPIRE Server is not yet able to validate SVIDs having SPIFFE IDs with a `stocksmarket.org` trust domain. To make this possible, the stocks market folks must run the following on the node they have SPIRE Server running:

```
stocks-market> spire-server experimental bundle show > stocksmarket.org.bundle
```

Then the stocks market folks must give a copy of this file to the broker folks, so they can store this trust bundle on their SPIRE Server and associate it with the `stocksmarket.org` trust domain. To achieve this, the broker folks must run the following on the node where they have SPIRE Server running:

```
broker> spire-server experimental bundle set -id spiffe://stocksmarket.org -path /some/path/stocksmarket.org.bundle
```

Now both SPIRE Servers can validate SVIDs having SPIFFE IDs with each other's trust domain, thus both can start fetching trust bundle updates from each other's federation endpoints. Also, as of now they can create registration entries for federating.

# Create registration entries for federation

Now that they are able to create registration entries to federate with each other, let's see how they can actually create them.

To simplify things, we are going to suppose that the webapp and the quotes service are running both on Linux boxes, one owned by the broker and the other owned by the stocks market organization. Since they are using SPIRE, each Linux box also has a SPIRE Agent installed. In addition to this, the webapp is run using the `webapp` user, and the quotes service is run using the `quotes-service` user.

Then, in the SPIRE Server node of the broker, they must create a registration entry as follows:

```
broker> spire-server entry create \
	-parentID <SPIRE Agent's SPIFFE ID> \
	-spiffeID spiffe://broker.org/webapp \
	-selector unix:user:webapp \
	-federatesWith "spiffe://stocksmarket.org"
```

Once this registration entry is created, when the webapp asks for an SVID it will get one having the `spiffe://broker.org/webapp` identity, along with the trust bundle associated to the `stocksmarket.org` trust domain, due to the use of the `-federateWith` flag when creating the registration entry. Worth to mention that if the `-federateWith` flag would not be used, federation would not work.

At the stocks market service side, they must create a registration entry as follows:

```
stocks-market> spire-server entry create \
	-parentID <SPIRE Agent's SPIFFE ID> \
	-spiffeID spiffe://stocksmarket.org/quotes-service \
	-selector unix:user:quotes-service \
	-federatesWith "spiffe://broker.org"
```

Similarly, once this registration entry is created, when the quotes service asks for an SVID it will get one having the `spiffe://stocksmarket.org/quotes-service` identity, along with the trust bundle associated to the `broker.org` trust domain.

That is about it, now all the pieces are together to make federation work and see how the webapp is able to communicate with the quotes service despite having identities with different trust domains.

# Federation Example with SPIRE 0.11.0

This section explains how to try the example implementation of the scenario described previously.

## Requirements

- Go 1.14
- docker-compose

## Build

```
$ ./build.sh
```

## Run

```
$ docker-compose up -d
```

This starts the SPIRE Servers and the applications.

## Start SPIRE Agents 

```
$ ./1-start-spire-agents.sh
```

## Bootstrap Federation

```
$ ./2-bootstrap-federation.sh
```

## Create Workload Registration Entries

```
$ ./3-create-registration-entries.sh
```

After running this script, it may take some seconds for the applications to receive their SVIDs and trust bundles. 

## See it working on the browser

Open up a browser to http://localhost:8080/quotes and you should see a grid of randomly generated phony stock quotes that are updated every 1 second.

## Clean up

```
$ docker-compose down
```

