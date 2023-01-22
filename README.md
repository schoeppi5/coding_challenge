# Coding challenge

- [Coding challenge](#coding-challenge)
  - [Time spent](#time-spent)
  - [Step 0.1: Creating Kubernetes cluster](#step-01-creating-kubernetes-cluster)
  - [Step 0.2: Deploying monitoring solution](#step-02-deploying-monitoring-solution)
  - [Step 0.3: Templating the demo application](#step-03-templating-the-demo-application)
  - [Challenge 1: Logging](#challenge-1-logging)
  - [Challenge 2: Autoscaling](#challenge-2-autoscaling)
  - [Challenge 3: Templating issues](#challenge-3-templating-issues)
    - [Syntactical errors](#syntactical-errors)
    - [Manifest validation](#manifest-validation)
    - [Best practices](#best-practices)
    - [Implementation](#implementation)
    - [Honorable mentions](#honorable-mentions)
  - [Challenge 4: Rollback](#challenge-4-rollback)
  - [Metrics](#metrics)
  - [Challenge 6: CI/CD tool choice](#challenge-6-cicd-tool-choice)
  - [Additional challenges](#additional-challenges)
    - [Ingress controller](#ingress-controller)
    - [Alerting](#alerting)
    - [TSDB writing](#tsdb-writing)
    - [Secrets in GIT](#secrets-in-git)
    - [Remove clear secrets from GIT](#remove-clear-secrets-from-git)
  - [Conclusion](#conclusion)


## Time spent

- Initial setup: ~40min
- App setup: ~15min

**Sub-total setup: 55min**

- Logging: 90min
- HPA: 50min
- Templating: 44min
- Rollback: 20min
- Metrics: 7min
- CI/CD tool choice: 8min

**Sub-total challenges: 219min**

- Additionals: 25min

**Total: 55min + 219min + 25min = 299min**

> I am not sure, if the preparation time should be included here or not.
> I included it for completeness sake.

## Step 0.1: Creating Kubernetes cluster

I choose [kind](https://kind.sigs.k8s.io/) for my local cluster, because of it's simplicity and configurability, which might come in handy later on.

You can find the configuration used for the cluster in [./kind/config.yaml](kind/config.yaml).

## Step 0.2: Deploying monitoring solution

Prometheus and Grafana are set as requirements and the easiest way to deploy both and all the extra components needed for a comprehensive monitoring solution is the [kube-prometheus-stack Helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).

It also comes with the [Prometheus operator](https://github.com/prometheus-operator/prometheus-operator) originally developed at CoreOS, which will make integrating the demo application later on just a bit easier, thanks to its `Pod`- and `Servicemonitor` CRDs.

You can find the `values.yaml` used for the installation [here](k8s/helm/prometheus-operator/values.yaml).

Once the monitoring stack is running, execute

```bash
kubectl --context=kind-coding-challenge-cluster --namespace=monitoring port-forward services/monitoring-grafana 8080:80
```

and visit [http://localhost:8080](http://localhost:8080) to access Grafana.

The credentials are **admin:prom-operator**.

## Step 0.3: Templating the demo application

Since the challenge calls for all deployments to use some kind of templating, I am going to use `kustomize` for the demo application.
There are two reasons for this decision:

1. To introduce some variety into the project.
   A lot of the things I will deploy during this challenge are going to use Helm, so why not keep it interesting?
2. It is a very simple app.
   The app doesn't need a lot to work, so why overcomplicate?

I generated the deployment and the service with their respective `kubectl create` commands:

```bash
$ kubectl create deployment --image=gcr.io/kuard-demo/kuard-amd64:blue --dry-run=server --namespace=app --port=8080 --replicas=1 kuard -oyaml > k8s/manifests/deployment.yaml

$ k create service clusterip --dry-run=server --namespace app --tcp=8080:80 kuard -oyaml > service.yaml  
```

Then, I stripped out the unnecessary (runtime) bits such as `uid`, `creationTimestamp` and `status: {}` and added them to the kustomize directory.

I then added a label to tie the service and the pod resulting from the deployment together and used the *image transformer* to manage the image in the `kustomization.yaml` file.

You can find the demo application files [here](k8s/kustomize/kuard).

Once the app is running, execute

```bash
kubectl --context=kind-coding-challenge-cluster --namespace=app port-forward services/kuard 9090:80
```

and visit [http://localhost:9090](http://localhost:9090) to access the demo app.

With the setup out of the way, I can start with the first challenge! 🎉

## Challenge 1: Logging

The first question is, what a logging solution could look like in a Kubernetes environment.

Having Grafana as a requirement and me having previous experience with it, made picking [Grafana Loki](https://grafana.com/docs/loki/latest/) in combination with [Grafana Promtail](https://grafana.com/docs/loki/latest/clients/promtail/) a no-brainer.

The idea behind it is quite simple:
- Use Loki as the aggregation tool ("Like Prometheus, but for Logs!" (verbatim from the Loki logo))
- Use Promtail as the collection agent

The difference between Loki and Prometheus is, that Loki uses a *push* rather than a *pull* model. Where Prometheus polls each endpoint,
Promtail collects all logs from the containers *stdout* and *pushes* them to Loki.

Well, technically, Promtail scrapes the logs of the containers from the hosts filesystem. That's the reason, why Promtail mounts both `/var/lib/docker/containers` and `/var/log/pods` from the host machine.

So in essence:

container --logs--> stdout --*--> /var/log/pods <-- Promtail --> Loki <--query-- Grafana 

> \* I am guessing this is done by the kubelet, but I am not entirely sure here

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

Now this is well and good, but I don't want to configure the Grafana datasource every time I reinstall it or Grafana is restarted.
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

## Challenge 2: Autoscaling

To be honest, this challenge had me stumped for a moment. The way it is phrased had my mind going towards load-testing, but I couldn't
really think of a Kubernetes native way to implement something like that aside from creating a Job/Pod that would just fire as many
HTTP requests as it could. But that would neither assure an application can handle high real-world loads, nor would it be a particular
meaningful test.

But then the *"assure"* had me going towards autoscaling and particularly `Horizontal Pod Autoscaling` (aka. HPA).

So I went in that direction and hope this satisfies the challenge.

Implementing a rudimentary autoscaling setup is - again - really straight forward:

1. Create an HPA resource using the built-in kubectl command:
  
  ```bash
  kubectl autoscale --namespace app deployment kuard --min 1 --max 10 --cpu-percent=80 --name=kuard --output yaml --dry-run=client > k8s/kustomize/kuard/hpa.yaml
  ```
   > It wouldn't let me do the server-side render (`--dry-run=server`) for some weird reason and just quit with:
   > `error: /, Kind= doesn't support dryRun`
   > So I just went with the client-side render and that worked
2. Add it to the kustomize directory and add it to the `resources` array in the `kustomization.yaml`
   > Kustomize has a built-in `nameReference` for Deployment -> HorizontalPodAutoscaler, which keeps them linked together

I went with `cpuPercentage` as the auto-scaling metric, since HTTP requests to stateless applications - in my experience - usually
are more CPU than Memory heavy. In a more sophisticated autoscaling setup, this could be tweaked in two main ways:

1. Use a custom metric like HTTP requests rate, or average response time
2. Go further with the autoscaling and implement a *cluster-autoscaler*, since the applications capacity is currently limited by the
   size of the cluster

And, of course, I forgot about the tiny detail, that a metrics based autoscaler actually needs metrics:
![hpa_metrics](img/hpa_metrics.png)

But that is easily fixed by providing an implementation for the Kubernetes metrics API. There are two, that I am currently aware of:

1. [Kubernetes SIG Metrics server](https://github.com/kubernetes-sigs/metrics-server)
2. [Kubernetes SIG Prometheus adapter](https://github.com/kubernetes-sigs/prometheus-adapter)

Both would work, but I think it is easiest when all metrics used by a system have a single source of truth. So I am going with the *Prometheus adapter*, which uses Prometheus as its datasource and converts those metrics to the Kubernetes metrics API format.

The great Prometheus community maintains a Helm Chart for it, so I am going to use that to install it.

After installing it and testing it, I noticed, that the HPA still wasn't picking up any metrics. After a quick look into the documentation on how to configure it, I noticed, that I forgot to add the config for the `pod.metrics` API.

What had me worried was, that after that fix `kubectl top` was still showing me `0m` CPU load for the app:
![metrics_low](img/metrics_low.png)

Guessing there was something wrong with my Prometheus setup, I quickly did a `kubectl top` on the Grafana pod:
![metrics_working](img/metrics_working.png)

which, to my great relieve, showed me, that everything was working as intended, but the demo app just has a ridiculously low CPU utilization.

And now, after checking the HPA again:
![hpa_working](img/hpa_working.png)

everything was working as intended! 😄

## Challenge 3: Templating issues

How one can spot issues with templating, actually depends on what one considers as an issue. This is an interesting question and has
many ways to go about this.

### Syntactical errors

Depending on the templating tool used, these are generally easy to spot before an application is deployed.

**Kustomize** is straight forward here. It will spot YAML format errors (wrong indentation mainly) and will complain, if it can't accumulate all resources. This should cover the basic errors in how the Kustomize structure is setup and if the resources are formatted correctly.

**Helm** has similar possibilities. It comes with a `lint` sub-command, which generally spots most issues in the templating of a chart.
It also has a `dry-run` capability, with which I can assure, that the chart actually renders to something resembling a Kubernetes manifest.

### Manifest validation

Neither tool actually makes sure, that what it produces are valid Kubernetes Manifests. I can use a tool like [kubeconform](https://github.com/yannh/kubeconform) (which is inspired by `kubeeval`) to make sure, that all manifests a templating tool produces are actually valid Kubernetes manifests. It does that, by comparing all generated manifests (obtained by either doing a `kustomize build` or a `helm template`) to their respective OpenAPIv3 specs. You can even extend these specs with the ones for CRDs to cover all manifests.

[Pluto](https://github.com/FairwindsOps/pluto) can also help to spot soon to be deprecated APIs early enough, before they are removed from Kubernetes.

At this point, we have validated, that the Helm chart / Kustomize config will produce valid, appliable Kubernetes manifests.

### Best practices

If we want to take this one step further, we can also check for common best-practices.
[kube-score](https://github.com/zegl/kube-score) can provide common best-practices for a lot of Kubernetes resources.

This way, we can catch stuff like:

- not set resource limits/requests
- missing probes
- Statefulsets without a headless service

and many more, before the application ever gets deployed.

Another way to go about this is with policies. Tools like [Datree](https://www.datree.io/) can check manifests against policies defined in a Kubernetes cluster, before they are deployed.
These tools are most often combined with `ValidatingWebhooks`, which block misconfigured deployments at deploy-time.

### Implementation

Since the challenge actually calls for an implementation, I am going to focus on `kubeconform` and `kube-score`.
You can find the implementation in [the Kustomize directory](k8s/kustomize/kuard/check.sh).

After changing the `containerPort` in the deployment from a number to a string, `kubeconform` complained about it:
![kubeconform](img/kubeconform.png)

And `kube-score` actually found quite a lot of infringements:
![kube-score_fail](img/kube-score_fail.png)

Damn 😑. Let's fix those.

After fixing these failures, `kube-score` is happy again:
![kube-score_success](img/kube-score_success.png)

> To be honest, I did ignore three quality gates: Regarding PodDisruptionBudget, NetworkPolicy and PodAntiAffinity
> since they don't usefully apply to the demo use-case.

### Honorable mentions

[Kubernetes Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) can help secure pods,
by warning / enforcing security best-practices defined by the Kubernetes maintainers on a namespace level.
This doesn't really fit the challenge, since this is only effective at deploy-time.

There are also a lot of useful plugins for IDEs and editors, that offer IntelliSense for Helm and Kubernetes objects.

## Challenge 4: Rollback

I just noticed, that I am running a bit out of time here, so I am going to try to keep my answers a bit more precise and to the point.

The idea here is, if I rollout a new version of an app and notice something is wrong with the new version, I want to roll back to the previous version.

There are again multiple ways to go about this:

- Kubernetes has a built-in feature, that a Deployment keeps (by default) the last ten ReplicaSets.
- Helm keeps all previously applied configurations of a release in secrets, so you can always do a `helm rollback` to a specific revision
- You can employ more sophisticated deployment approaches such as Blue/Green deployments or canary releases.
  Depending on their implementation, they use one of the mechanisms described above to enable the user to switch between two versions
  deployed simultaneously

Since I am using kustomize to deploy the app, I am going to use the built-in Kubernetes way of doing it.

First, we check the rollout history for the deployed app:
![rollout_history](img/rollout_before.png)

Then we apply our change in version:
![apply](img/kustomize_apply.png)

We can see, that the pod was updated:
![new pod](img/new_pod.png)

Now we can do a rollback (or more accurately a `rollout undo`):
![rollback](img/rollback.png)

We can check, that the old ReplicaSet was scaled up again: 
![ReplicaSets](img/replicasets.png)

And see, that a new (old) pod was created:
![old pod](img/old_pod.png)

## Metrics

The application actively exports metrics on `/metrics` ([http://localhost:9090/metrics](http://localhost:9090/metrics)).
Besides the normal Golang metrics (go-routine count, version, etc.), we can also find specific metrics, such as:

- HTTP requests / response duration / size
- Process information (open FD, start time, memory consumption, etc.)
- HTTP request duration per path and categorized in buckets

Beside the metrics the application exports, we can also get metrics regarding the application from other pieces of the infrastructure:

- cAdvisor (built into the Kubelet) tells us everything about the containers that make up the application
- Kube-state-metrics tells us everything about the Kubernetes-level resources (pods, services, etc.)

## Challenge 6: CI/CD tool choice

There is a huge number of CI/CD tools to choose from here, so I am going to choose the once I am most familiar with or I see as a good fit.

For building, testing and packaging / delivering the app, I would choose [GitHub Actions](https://github.com/features/actions).

- It is directly integrated into GitHub, where this repository is hosted
- It can trigger builds on various different events, such as pushes, PR opened, merges and lots more
- It is easy to use with an incredible number of officially and community maintained actions ready for use
- I have (some) previous experience with it, as we started using it at my current company

For deploying the app to a Kubernetes cluster, I would choose [Flux CD](https://fluxcd.io/).

- It has recently reached *Graduate* status within the CNCF, which reflects the maturity of the product
- It brings a wealth of useful features to the table, such as Helm integration, Kustomize support, support for different sources (OCI, Git, HelmRepository), integration with Flagger (Deployment tool)
- It is easy to setup and integrates well with GitHub (using `flux bootstrap` sets it up in a cluster and Flux manages itself)
- I have about a year worth of experience with it and know my way around it

## Additional challenges

### Ingress controller

Traffic is usually split in two categories: Ingress and Egress traffic, deriving from the latin *gressere* (to walk) and *in* and *ex* for in and out respectively.

So, therefore, an Ingress controller manages how traffic comes into a Kubernetes cluster.
In essence it is a reverse proxy exposed to the outside by a Service of type `LoadBalancer`
or `NodePort` (or by accessing the host network), that accepts incoming connections and routes them using services to the correct applications.

The configuration for such an Ingress controller is managed by Ingress resources. These contain the necessary information telling the Ingress controller how to get to the application, what hostname to use for it, which Service is responsible for which subpath, which TLS certificate to use and much more.

An example ingress resource for the demo application could look like this:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kuard
  namespace: app
spec:
  rules:
  - host: demo.local
    http:
      paths:
      - backend:
          service:
            name: kuard
            port:
              number: 80
        path: /
        pathType: Exact
```

### Alerting

Alerting within Kubernetes can come in many different shapes and sizes. Even the rather simple monitoring setup used in this demo already has two very common ways to facilitate alerting.

Either Grafana or [Prometheus Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/) could be used to achieve similar results.

Alertmanager is generally more flexible when it comes to what you want to alert on
and integrates very well with Prometheus.

Grafana on the other hand, has taken a very central place in the observability market, integrates with pretty much any monitoring and alerting system out there, even Alertmanager.

The general idea of alerting is, that if a certain query produces an outcome greater or lesser a certain threshold, I want to now about it. This also extends to outages, but the idea stays the same.

What would this look like? In this specific demo, Prometheus operator can also operate Alertmanager installations and comes with CRDs to define so called Prometheus rules. These rules essentially contain the query, the threshold and some metadata. Alertmanager than looks at the firing alerts and based on its config and the alert, decides, where this alert should go to.

### TSDB writing

Prometheus main way of getting metrics in its TSDB is by ingesting them. This is essentially the process after scraping them from a target. The metrics get labeled and sorted in their timeseries.

There is however another way to get metrics into Prometheus. Prometheus introduced the Remote write API, that enables other components to write metrics more or less directly to the TSDB without having to go through scraping.

This is for example used by Grafana Tempo to write metrics derived from traces directly to Prometheus to account these metrics to the correct services.

### Secrets in GIT

I now of two ways to keep secrets in GIT:

- Mozilla SOPS
- Bitnami Sealed secrets

Mozilla SOPS uses a GPG key to encrypt secrets before they are committed to a GIT repository, which are unencrypted during runtime by e.g. Flux CD. This requires both the developer as well as the infrastructure using the secret to have the key. This can become challenging over time to keep track of the key.

Bitnami sealed secrets uses a Kubernetes controller to decrypt secrets, which are encrypted on the Developer side using a CLI in such a way, that only the controller can decrypt them.

### Remove clear secrets from GIT

This really depends on the scope. Was the secret only committed to a branch in the last commit, remove it from the local repository, stage the change and amend the last commit.

Was the secret committed a while ago and maybe even merged, this becomes a lot more complicated. It requires not only removing it from the current HEAD, but also from the complete commit history, which becomes messy fast.

`git filter-branch` can come in handy here, but [git-filter-repo](https://github.com/newren/git-filter-repo/) seems to be the better, more performant alternative.

## Conclusion

I had fun completing this challenge. I was able to draw from previous experience on pretty much every challenge, but I still learned a new thing or two. For example, I knew about the rollback feature in Kubernetes, but never actually had to use it before.

I didn't find the challenge particularly difficult in any part, since I knew how I wanted to approach each topic and had a clear path in mind, except for the autoscaling thing.

With ~ 244 minutes I am right on target, but I would contribute roughly 40 - 50% to writing documentation and I am now questioning, if I am a slow typist.

At this point I want to thank you for this challenge, since it gave me the opportunity to revisit tools and topics I haven't actively worked on for some time and I genuinely had a good time doing it.