#!/bin/bash

set -e

# create cluster
if [[ $(kind get clusters | grep coding-challenge-cluster) == "" ]]; then
    kind create cluster --config=./kind/config.yaml
fi

# deploy monitoring stack
helm upgrade \
    --kube-context kind-coding-challenge-cluster \
    --namespace monitoring \
    --create-namespace \
    --install \
    monitoring \
    prometheus-community/kube-prometheus-stack \
    -f ./k8s/helm/prometheus-operator/values.yaml