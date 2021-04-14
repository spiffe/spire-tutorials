kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/spire-server.yaml
kubectl rollout status deployment/spire-server -n spire

kubectl apply -f k8s/spire-agent.yaml
kubectl rollout status daemonset/spire-agent -n spire

kubectl apply -f k8s/workload.yaml
kubectl rollout status deployment/example-workload -n spire
