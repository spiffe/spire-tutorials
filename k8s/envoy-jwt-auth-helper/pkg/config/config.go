package config

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"

	"github.com/hashicorp/hcl"
)

// Config available configurations
type Config struct {
	SocketPath string `hcl:"socket_path"`
	Host       string `hcl:"host"`
	Port       int    `hcl:"port"`
	JWTMode    string `hcl:"jwt_mode"`
	Audience   string `hcl:"audience"`
}

//ParseConfigFile parse config file
func ParseConfigFile(filePath string) (*Config, error) {
	data, err := ioutil.ReadFile(filePath)
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

	return c, nil
}
