# Coding challenge

## Time spent

- Initial setup: ~40min
- App setup: ~15min
- Logging: 90min
- HPA: tbd 
- Templating: tbd
- Rollback: tbd
- Metrics: tbd
- CI/CD tool choice: tbd

**Total: tbd**

> Please keep in mind, that while some timestamps or uptimes in the screenshots and elsewhere might suggest, that I took way longer
> for the tasks than I indicated above, but I did take breaks in between and didn't finish it all in one sitting 😉


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

With the setup out of the way, I can start with the first challenge! 🎉

## Challenge 1: Logging

The first question is, what a logging solution could look like in a Kubernetes environment.

Having Grafana as a requirement and me having previous expirience with it, made picking [Grafana Loki](https://grafana.com/docs/loki/latest/) in combination with [Grafana Promtail](https://grafana.com/docs/loki/latest/clients/promtail/) a no-brainer.

The idea behind it is quite simple:
- Use Loki as the aggregation tool ("Like Prometheus, but for Logs!" (verbatim from the Loki logo))
- Use Promtail as the collection agent

The difference between Loki and Prometheus is, that Loki uses a *push* rather than a *pull* model. Where Prometheus polls each endpoint,
Promtail collects all logs from the containers *stdout* and *pushes* them to Loki.

Well, technically, Promtail scrapes the logs of the containers from the hosts filesystem. That's the reason, why Promtail mounts both `/var/lib/docker/containers` and `/var/log/pods` from the host machine.

So in essence:

container --logs--> stdout --*--> /var/log/pods <-- Promtail --> Loki <--query-- Grafana 

> \* I am guessing this is done by the kubelet, but I am not entirly sure here

Installing both components is rather straight-forward:
- Customize the `values.yaml` file shipped with the Helm chart
- Look up some configuration options
  I was at first a bit confused, how I can tell the Helm chart to install Loki in single-binary mode, but discovered, that it does that
  on its own, once you tell it to use the filesystem for storage (https://grafana.com/docs/loki/latest/installation/helm/configure-storage/)
- Install the Helm chart

After that is done, we can be happy, that all the pods are starting up correctly:
![logging_startup.png](img/logging_startup.png)

And we can even see logs, once Loki is configured as a datasource in Grafana:
![loki_datasource](img/loki_datasource.png)

![logs](img/logs.png)

Now this is well and good, but I don't want to configure the Grafana datasource everytime I reinstall it or Grafana is restarted.
Luckily, the Grafana Helm chart (part of the kube-prometheus-stack Helm chart) comes with a handy sidecar container enabling me to
define a datasource in a configmap and the sidecar then updates Grafana during runtime using the API.

All we need to add to the `values.yaml` of the Helm chart is:

```yaml
grafana:
...
additionalDataSources:
    - name: Loki
      type: loki
      access: proxy
      url: http://logging.logging.svc.cluster.local:3100
      jsonData:
        maxLines: 1000
```

and now, even after deleting the Grafana pod:

![delete_grafana](img/delete_grafana.png)

the datasource is still there:

![datasources](img/datasources.png)


