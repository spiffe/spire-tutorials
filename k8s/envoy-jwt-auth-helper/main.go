package main

import (
	"context"
	"flag"
	"log"
	"net"
	"strconv"

	auth "github.com/envoyproxy/go-control-plane/envoy/service/auth/v3"
	authExternal "github.com/scytaleio/envoy-jwt-auth-helper/pkg/auth"
	"github.com/scytaleio/envoy-jwt-auth-helper/pkg/config"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
	"google.golang.org/grpc"
)

func main() {
	configFilePath := flag.String("config", "envoy-jwt-auth-helper.conf", "Path to configuration file")
	flag.Parse()

	c, err := config.ParseConfigFile(*configFilePath)
	if err != nil {
		log.Fatalf("Error parsing configuration file: %v", err)
	}

	lis, err := net.Listen("tcp", net.JoinHostPort(c.Host, strconv.Itoa(c.Port)))
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	s := grpc.NewServer([]grpc.ServerOption{grpc.MaxConcurrentStreams(10)}...)

	// Create options to configure Sources to use socket path passed via config file.
	clientOptions := workloadapi.WithClientOptions(workloadapi.WithAddr(c.SocketPath))

	// Create a JWTSource to validate provided tokens from clients
	jwtSource, err := workloadapi.NewJWTSource(context.Background(), clientOptions)
	if err != nil {
		log.Fatalf("Unable to create JWTSource: %v", err)
	}
	defer jwtSource.Close()

	authExternal, err := authExternal.NewAuthServer(c.SocketPath, c.Audience, c.JWTMode, jwtSource)
	if err != nil {
		log.Fatalf("Error creating AuthServer: %v", err)
	}

	auth.RegisterAuthorizationServer(s, authExternal)

	log.Printf("Starting gRPC Server at %d", c.Port)
	s.Serve(lis)
}
