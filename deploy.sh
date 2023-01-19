#!/bin/bash

set -e

# vars
K8S_CONTEXT=kind-coding-challenge-cluster
MONITORING_NAMESPACE=monitoring
LOGGING_NAMESPACE=logging
APP_NAMESPACE=logging

# create cluster
if [[ $(kind get clusters | grep coding-challenge-cluster) == "" ]]; then
    kind create cluster --config=./kind/config.yaml
fi

# deploy monitoring stack
helm upgrade \
    --kube-context $K8S_CONTEXT \
    --namespace $MONITORING_NAMESPACE \
    --create-namespace \
    --install \
    monitoring \
    prometheus-community/kube-prometheus-stack \
    -f ./k8s/helm/prometheus-operator/values.yaml

# deploy demo app
kubectl apply -k ./k8s/kustomize/kuard

# challenge 1: Install logging (Grafana Loki/Promtail)
helm upgrade \
    --install \
    --create-namespace \
    --namespace $LOGGING_NAMESPACE \
    --kube-context $K8S_CONTEXT \
    --values ./k8s/helm/loki/values.yaml \
    loki grafana/loki
helm upgrade \
    --install \
    --create-namespace \
    --namespace $LOGGING_NAMESPACE \
    --kube-context $K8S_CONTEXT \
    --values ./k8s/helm/promtail/values.yaml\
    promtail grafana/promtail