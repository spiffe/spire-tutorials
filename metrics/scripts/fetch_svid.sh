#/bin/bash

set -e

echo "Will call api fetch x509 100 times in a random interval between 1 and 10 of seconds."
for ((i=0;i<100;i++)); do
    docker-compose exec -u 1001 -T spire-agent \
        /opt/spire/bin/spire-agent api fetch x509 \
        -socketPath /opt/spire/sockets/workload_api.sock > /dev/null
    sleep $(( $RANDOM % 10 + 1 ))
    continue
done

echo "Process completed."
exit 0
