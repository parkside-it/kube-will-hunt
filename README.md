# kube-will-hunt

![GitHub Workflow Status](https://img.shields.io/github/workflow/status/parkside-it/kube-will-hunt/build)
![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/parkside-it/kube-will-hunt?sort=semver)
![Docker Pulls](https://img.shields.io/docker/pulls/parkside/kube-will-hunt)
![GitHub](https://img.shields.io/github/license/parkside-it/kube-will-hunt)

Small cleanup scripts packaged into docker images to clean up old feature branches in Kubernetes clusters.

This repo includes a version for bare-metal and AWS EKS clusters.
Releases are pushed to [DockerHub](https://hub.docker.com/r/parkside/kube-will-hunt).

### What is that name?

We named this tool after the protagonist of the movie Good Will Hunting.
Will starts his journey as an unrecognised genius who works as a janitor at MIT.

Alternatively, you can think about it as a tool which will hunt down your unused resources!


## How it works
This tool takes care of your old feature branch CI deployments.

If a branch was merged into master/main, the `kube-will-hunt` docker image should be run.
It will fetch the current branches from GitHub and will compare against the branch deployments in your cluster.
If it finds deployments where the corresponding branch on GitHub is already deleted, it will delete the kubernetes
resources belonging to that branch.

### Features
* Option for dry runs to see what the branch cleaner would do
* Possibility to also clean kubernetes CRDs
* Option to exclude whitelisted resource/branch names
* Option to use different selectors to find kubernetes resources to clean

## Configuration
### Volumes
`kube-will-hunt` needs a valid kubeconfig file mounted as a volume.
The path where the file is mounted should be passed into the container through `$KUBECONFIG_PATH`.

### Common environment variables
| Variable | Required | Default | Example | Description |
|---|---|---|---|---|
| `REPO_URL` | yes |  | git@github.com:parkside-it/example-repo.git | Full SSH repo URL to fetch the current branches from |
| `KUBECONFIG_PATH` | yes |   | `/opt/kubeconfig` | Kubeconfig that is used to access the k8s cluster for cleanup |
| `KUBECTL_VERSION` | no | `1.16.11` | `1.18.15` | This version of kubectl will be downloaded and used |
| `K8S_NAMESPACE` | yes |  | `some-namespace` | This k8s namespace will be cleaned up |
| `GITHUB_TOKEN` | yes |  | `your-token` | This token is used to access private GitHub repos |
| `SELECTOR` | no | `label_key=branch` | `label_key=app` | This k8s selector will be used to find old resources that need cleanup |
| `EXTRA_PERSIST_VALUES` | no | `""`  | `staging,feature-to-keep` | Comma separated list of names that should not be cleaned up |
| `CRDS` | no | `""` | `SealedSecret` | Comma separated list of custom k8s resource definitions that should also be taken into account during cleanup |
| `DRY_RUN` | no | `0` | `1` or `0` | If this is set to `1`, then the cleanup will only check what to clean but not delete anything |

### Flavor specific environment variables
#### AWS

| Variable | Required | Default | Example | Description |
|---|---|---|---|---|
| `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` | yes |  | `$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` | Used for authentication to AWS |

You can find additional documentation inside the cleanup scripts for [AWS](/aws/cleanup.sh) and [bare-metal](/bare-metal/cleanup.sh).

## Example Usages
### Bare-metal clusters

```shell
docker pull parkside/kube-will-hunt:latest-bare-metal
docker run \
  -e "REPO_URL=github-user/github-repo" \
  -e "K8S_NAMESPACE=some-namespace" \
  -e "SELECTOR=label_key=branch" \
  -e "KUBECONFIG_PATH=/path/to/the/mounted/kubeconfig" \
  -e "GITHUB_TOKEN=your-github-token" \
  -e "KUBECTL_VERSION=1.18.15" \
  -e "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" \
  -v "/hostpath/to/kubeconfig:/path/to/the/mounted/kubeconfig" \
  parkside/kube-will-hunt:latest-bare-metal
```

### AWS EKS clusters
The `kube-will-hunt` image for AWS clusters is intended for use in AWS CodeBuild pipelines.
It makes use of the `$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` environment variable 
which points to valid AWS credentials that are used to access the AWS EKS cluster.
```shell
docker pull parkside/kube-will-hunt:latest-aws
docker run \
  -e "REPO_URL=github-user/github-repo" \
  -e "K8S_NAMESPACE=some-namespace" \
  -e "SELECTOR=label_key=branch" \
  -e "KUBECONFIG_PATH=/path/to/the/mounted/kubeconfig" \
  -e "GITHUB_TOKEN=your-github-token" \
  -e "KUBECTL_VERSION=1.18.15" \
  -e "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" \
  -v "/hostpath/to/kubeconfig:/path/to/the/mounted/kubeconfig" \
  parkside/kube-will-hunt:latest-aws
```

## License
MIT License
