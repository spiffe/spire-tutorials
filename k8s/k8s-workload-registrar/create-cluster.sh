sed -i.bak "s#K8SDIR#${PWD}/mode-webhook/k8s#g" kind-config.yaml
rm kind-config.yaml.bak
kind create cluster --name example-cluster --config kind-config.yaml
