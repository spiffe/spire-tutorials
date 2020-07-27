#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

(cd src/broker-webapp && GOOS=linux go build -v -o $DIR/docker/broker-webapp/broker-webapp)
(cd src/stock-quotes-service && GOOS=linux go build -v -o $DIR/docker/stock-quotes-service/stock-quotes-service)

docker-compose -f docker-compose.yml build