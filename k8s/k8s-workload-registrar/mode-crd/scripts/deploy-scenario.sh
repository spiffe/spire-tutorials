kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/spiffeid.spiffe.io_spiffeids.yaml
kubectl apply -f k8s/k8s-workload-registrar-cluster-role.yaml
kubectl apply -f k8s/spire-server.yaml
kubectl apply -f k8s/k8s-workload-registrar-configmap.yaml
kubectl apply -f k8s/k8s-workload-registrar-statefulset.yaml

kubectl rollout status statefulset/spire-server -n spire

kubectl apply -f k8s/spire-agent.yaml

kubectl rollout status daemonset/spire-agent -n spire

kubectl apply -f k8s/workload.yaml # doesnt work
