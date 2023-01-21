#!/bin/bash

set -e # We wan't the script to stop, when it encounters an error

# Verify, that kustomize can build the config
kustomize build . > /dev/null

# Check, that all manifests conform to their OpenAPIv3 schemas
kustomize build . | kubeconform -

# Check, that all manifests use common best-practices
kustomize build . | kube-score score - 