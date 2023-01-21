#!/bin/bash

## How to use this:
## Make sure, you deploy the app first with `blue` set as the newTag in kustomization.yaml
## Then change it to `green`

kubectl rollout history -n app deployment kuard

kubectl apply -k .

kubectl rollout history -n app deployment kuard

kubectl get rs -n app

kubectl rollout undo -n app deployment kuard

kubectl get rs -n app