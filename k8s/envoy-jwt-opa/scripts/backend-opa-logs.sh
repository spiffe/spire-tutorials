POD=$(kubectl get pod -l app=backend -o jsonpath="{.items[0].metadata.name}")
kubectl logs $POD -c opa | jq .
