package config

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/hashicorp/hcl"
	"github.com/kelseyhightower/envconfig"
)

const EnvVarPrefix = "SPIRE_ENVOY_JWT_HELPER"

// Config available configurations
type Config struct {
	SocketPath string `hcl:"socket_path" envconfig:"SOCKET_PATH"`
	Host       string `hcl:"host"        envconfig:"HOST"`
	Port       int    `hcl:"port"        envconfig:"PORT"`
	JWTMode    string `hcl:"jwt_mode"    envconfig:"JWT_MODE"`
	Audience   string `hcl:"audience"    envconfig:"AUDIENCE"`
}

// ParseConfigFile parse config file
func ParseConfigFile(filePath string) (*Config, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			msg := "could not find config file %s: please use the -config flag"
			p, err := filepath.Abs(filePath)
			if err != nil {
				p = filePath
				msg = "config file not found at %s: use -config"
			}
			return nil, fmt.Errorf(msg, p)
		}
		return nil, err
	}

	c := new(Config)
	if err := hcl.Decode(c, string(data)); err != nil {
		return nil, fmt.Errorf("unable to decode configuration: %v", err)
	}

	err = envconfig.Process(EnvVarPrefix, c)
	if err != nil {
		return nil, fmt.Errorf("environment variable configuration overwrite failed: %v", err)
	}
	c.Print()

	return c, nil
}

func (c *Config) Print() {
	msg := "loaded config:\nSocketPath: %s \nHost: %s\nPort: %d\nJWTMode: %s\nAudience: %s\n"
	log.Printf(msg, c.SocketPath, c.Host, c.Port, c.JWTMode, c.Audience)
}
