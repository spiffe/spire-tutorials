package auth

import (
	"context"
	"fmt"
	"log"
	"strings"

	core "github.com/envoyproxy/go-control-plane/envoy/config/core/v3"
	auth "github.com/envoyproxy/go-control-plane/envoy/service/auth/v3"
	envoy_type "github.com/envoyproxy/go-control-plane/envoy/type/v3"
	"github.com/gogo/googleapis/google/rpc"
	"github.com/spiffe/go-spiffe/v2/svid/jwtsvid"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
	rpcstatus "google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// Mode type will define how this service will behave
type Mode int

const (
	// JWTInjection Mode will insert JWT in header
	JWTInjection Mode = 1 + iota
	// JWTSvidValidator Mode will validate JWT header
	JWTSvidValidator
)

func (m Mode) String() string {
	switch m {
	case JWTInjection:
		return "jwt_injection"
	case JWTSvidValidator:
		return "jwt_svid_validator"
	default:
		return fmt.Sprintf("UNKNOWN(%d)", m)
	}
}

// Config auth server config
type Config struct {
	// JWT Source used to verify token
	jwtSource *workloadapi.JWTSource
	// Expected audiences
	audience string
	// Defines how this service will behave
	mode Mode
}

// AuthServer implements auth.AuthorizationServer interface
type AuthServer struct {
	config *Config
}

// NewAuthServer creates a new Auth server according to the given config
func NewAuthServer(socketPath string, audience string, mode string, jwtSource *workloadapi.JWTSource) (*AuthServer, error) {
	var config = &Config{
		jwtSource: jwtSource,
		audience:  audience,
	}

	if mode != "" {
		var err error
		config.mode, err = parseJWTMode(mode)
		if err != nil {
			return nil, err
		}
	}

	log.Printf("Auth Server running in %s mode", config.mode)
	return &AuthServer{
		config: config,
	}, nil
}

// Check check
func (a *AuthServer) Check(ctx context.Context, req *auth.CheckRequest) (*auth.CheckResponse, error) {
	authHeader, ok := req.Attributes.Request.Http.Headers["authorization"]

	switch a.config.mode {
	case JWTInjection:
		if authHeader != "" {
			log.Printf("%v", fmt.Errorf("Request already contains an authorization header. Verify mode if expected mode is %s", a.config.mode))
			return forbiddenResponse("PERMISSION_DENIED"), nil
		}
		return a.injectJWTSVID(ctx)
	case JWTSvidValidator:
		var fields []string
		if ok {
			fields = strings.Split(authHeader, "Bearer ")
		}
		if len(fields) != 2 {
			log.Printf("Invalid or unsupported authorization header: %s", fields)
			return forbiddenResponse("Invalid or unsupported authorization header"), nil
		}
		token := fields[1]
		return a.validateJWTSVID(ctx, token)
	default:
		err := fmt.Errorf("Unknown server mode: %s", a.config.mode)
		log.Printf("Error selecting server mode. %v", err)
		return nil, err
	}
}

func (a *AuthServer) validateJWTSVID(ctx context.Context, token string) (*auth.CheckResponse, error) {
	// Parse and validate token against fetched bundle from jwtSource,
	_, err := jwtsvid.ParseAndValidate(token, a.config.jwtSource, []string{a.config.audience})
	if err != nil {
		log.Printf("Invalid token: %v\n", err)
		return forbiddenResponse("PERMISSION_DENIED"), nil
	}

	log.Printf("Token is valid")
	return okResponse(), nil
}

func (a *AuthServer) injectJWTSVID(ctx context.Context) (*auth.CheckResponse, error) {
	jwtSVID, err := a.config.jwtSource.FetchJWTSVID(ctx, jwtsvid.Params{
		Audience: a.config.audience,
	})
	if err != nil {
		log.Printf("Unable to fetch SVID: %v", err)
		return forbiddenResponse("PERMISSION_DENIED"), nil
	}

	response := &auth.CheckResponse{}
	headers := []*core.HeaderValueOption{
		{
			Append: &wrapperspb.BoolValue{
				Value: false, //Default is true
			},
			Header: &core.HeaderValue{
				Key:   "authorization",
				Value: fmt.Sprintf("Bearer %s", jwtSVID.Marshal()),
			},
		},
	}

	response.HttpResponse = &auth.CheckResponse_OkResponse{
		OkResponse: &auth.OkHttpResponse{
			Headers: headers,
		},
	}

	log.Printf("JWT-SVID injected. Sending response with %v new headers\n", len(response.GetOkResponse().Headers))
	return response, nil
}

func parseJWTMode(mode string) (Mode, error) {
	switch strings.ToLower(mode) {
	case "jwt_injection":
		return JWTInjection, nil
	case "jwt_svid_validator":
		return JWTSvidValidator, nil
	}
	return 0, fmt.Errorf("Unknown mode %s. Must be one of: jwt_injection, jwt_svid_validator", mode)
}

func okResponse() *auth.CheckResponse {
	return &auth.CheckResponse{
		Status: &rpcstatus.Status{
			Code: int32(rpc.OK),
		},
		HttpResponse: &auth.CheckResponse_OkResponse{
			OkResponse: &auth.OkHttpResponse{},
		},
	}
}

func forbiddenResponse(format string, args ...interface{}) *auth.CheckResponse {
	return &auth.CheckResponse{
		Status: &rpcstatus.Status{
			Code: int32(rpc.PERMISSION_DENIED),
		},
		HttpResponse: &auth.CheckResponse_DeniedResponse{
			DeniedResponse: &auth.DeniedHttpResponse{
				Status: &envoy_type.HttpStatus{
					Code: envoy_type.StatusCode_Forbidden,
				},
				Body: fmt.Sprintf(format, args...),
			},
		},
	}
}
