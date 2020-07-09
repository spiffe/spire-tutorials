#!/bin/bash

kubectl edit configmap backend-opa-policy-config

# Restart pod
kubectl scale deployment backend --replicas=0
kubectl scale deployment backend --replicas=1 