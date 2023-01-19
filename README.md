# Coding challenge

## Time spent

Initial setup: ~40min
App setup: tbd
Logging: tbd
HPA: tbd 
Templating: tbd
Rollback: tbd
Metrics: tbd
CI/CD tool choice: tbd

Total: tbd


## Step 0.1: Creating Kubernetes cluster

I choose [kind](https://kind.sigs.k8s.io/) for my local cluster, because of it's simplicity and configurability, which might come in handy later on.

You can find the configuration used for the cluster in [./kind/config.yaml](kind/config.yaml).

## Step 0.2: Deploying monitoring solution

Prometheus and Grafana are set as requirements and the easiest way to deploy both and all the extra components needed for a comprehensive monitoring solution is the [kube-prometheus-stack Helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).

It also comes with the [Prometheus operator](https://github.com/prometheus-operator/prometheus-operator) origianlly developed at CoreOS, which will make integrating the demo application later on just a bit easier, thanks to its `Pod`- and `Servicemonitor` CRDs.

You can find the `values.yaml` used for the installation [here](k8s/helm/prometheus-operator/values.yaml).

Once the monitoring stack is running, execute

```bash
kubectl --context=kind-coding-challenge-cluster --namespace=monitoring port-forward services/monitoring-grafana 8080:80
```

and visit [http://localhost:8080](http://localhost:8080) to access Grafana.

The credentials are **admin:prom-operator**.

## Step 0.3: Creating a Helm chart for the demo application

Since the challenge calls for all deployments to use some kind of templating, I am going to use `kustomize` for the demo application.
There are two reasons for this decision:

1. To introduce some varity into the project.
   Alot of the things I will deploy during this challenge are going to use Helm, so why not keep it interesting?
2. It is a very simple app.
   The app doesn't need a lot to work, so why overcomplicate?

I generated the deployment and the service with their respective `kubectl create` commands:

```bash
$ kubectl create deployment --image=gcr.io/kuard-demo/kuard-amd64:blue --dry-run=server --namespace=app --port=8080 --replicas=1 kuard -oyaml > k8s/manifests/deployment.yaml

$ k create service clusterip --dry-run=server --namespace app --tcp=8080:80 kuard -oyaml > service.yaml  
```

Then, I stripped out the unnecessary (runtime) bits such as `uid`, `creationTimestamp` and `status: {}` and added them to the kustomize directory.

I then added a lable to tie the service and the pod resulting from the deployment together and used the *image transformer* to manage the image in the `kustomization.yaml` file.

You can find the demo application files [here](k8s/kustomize/kuard).

Once the app is running, execute

```bash
kubectl --context=kind-coding-challenge-cluster --namespace=app port-forward services/kuard 9090:80
```

and visit [http://localhost:9090](http://localhost:9090) to access the demo app.