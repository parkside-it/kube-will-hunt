#!/bin/bash

# Purpose:
#
#   Compares k8s resources with repository branches. Deletes resources without a corresponding branch.
#
# Volumes:
#
#   - Kubeconfig:
#     The kubeconfig for the AWS EKS cluster that should be cleaned.
#     The file can be mounted into any directory (with proper access rights).
#     To tell the script where the config is mounted, use the KUBECONFIG_PATH env variable.
#
#
# Environment variables:
#
#   - REPO_URL
#     The full SSH URL of the remote repository. Currently, only GitHub repos are supported.
#     Example: "git@github.com:acme-inc/my-project.git"
#     Required: yes
#
#   - KUBECONFIG_PATH
#     The full path of the k8s config file which should be mounted there as a volume
#     Example: "/opt/kubeconfig"
#     Required: yes
#
#   - KUBECTL_VERSION
#     The kubectl version to use (should be close to cluster version, ideally match it).
#     Example: "1.18.15"
#     Required: no
#     Default: "1.16.11"
#
#   - K8S_NAMESPACE
#     The Kubernetes namespace to search for resources.
#     Example: "my-project"
#     Required: yes
#
#   - GITHUB_TOKEN
#     The GitHub access token that should be used to access the source repository.
#     Example: "a github access token"
#     Required: yes
#
#   - AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
#     This is a variable set by AWS ECS (and also AWS CodeBuild). It stores the path to the credentials for the
#     current IAM role that is used. This is needed so that the cleanup script can access the AWS EKS cluster
#     with the correct credentials.
#     This variable can be passed in as is (docker run -e $AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI)
#     Link for more info: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html
#     Required: yes
#
#   - SELECTOR
#     Defines how k8s resources will be matched against branches. Can be either "name", in order to match exact
#     resource names, or "label_key=<key>" to match one of the resource's labels.
#     Example: "label_key=somelabel"
#     Required: no
#     Default: "label_key=branch"
#
#   - EXTRA_PERSIST_VALUES
#     A comma-separated list of values to use with the selector and persist, besides existing branches. Useful for
#     one-off deployments
#     Example: "customer-preview,feature-to-keep,staging"
#     Required: no
#     Default: ""
#
#   - CRDS
#     A comma-separated list of additional custom resources to be pruned.
#     Example: "certificate,clusterissuer,ingressroute"
#     Required: no
#     Default: ""
#
#   - DRY_RUN
#     If enabled ("1"), no resources will actually be deleted.
#     Example: "1"
#     Required: no
#     Default: "0"

set -o nounset

echo "+++ Parsing inputs"
repo_slug=${REPO_URL#*":"}
repo_slug=${repo_slug%".git"}
selector=${SELECTOR:-"label_key=branch"}
kubectl_version=${KUBECTL_VERSION:-"1.16.11"}
extra_persist_values=${EXTRA_PERSIST_VALUES:-""}
crds=${CRDS:-""}
github_token=${GITHUB_TOKEN?Error: GITHUB_TOKEN is not defined}
kubeconfig_path=${KUBECONFIG_PATH?Error: KUEBCONFIG_PATH is not defined}
k8s_namespace=${K8S_NAMESPACE?Error: Kubernetes namespace is not defined}
dry_run=${DRY_RUN:-"0"}

if [ ! -f "$kubeconfig_path" ]; then
  echo "Error: Kubeconfig at the specified KUBECONFIG_PATH does not exist!"
  echo "Please check if the volume for it is mounted correctly."
  exit 1
fi

echo "Repo slug:               '$repo_slug'"
echo "Selector mode:           '$selector'"
echo "Extra values to persist: '$extra_persist_values'"
echo "CRDs:                    '$crds'"
echo "kubectl version:         '$kubectl_version'"
echo "Kubeconfig path:         '$kubeconfig_path'"
echo "Kubernetes namespace:    '$k8s_namespace'"
echo "Dry run:                 '$dry_run'"

echo "--- Downloading kubectl"
if ! curl -fsSLO "https://storage.googleapis.com/kubernetes-release/release/v$kubectl_version/bin/linux/amd64/kubectl"; then
  echo "Could not download kubectl"
  exit 1
fi
chmod +x ./kubectl
./kubectl version --client

echo "+++ Preparing list of resource kinds to target"
target_kinds=(
  ingress
  service
  deployment
  statefulset
  job
  cronjob
  persistentvolumeclaim
  configmap
  secret
)

if [[ -n $crds ]]; then
  IFS="," read -ra parsed_crds <<<"$crds"
  for kind in "${parsed_crds[@]}"; do
    target_kinds+=("$kind")
  done
fi

# when targeting by label, we can additionally prune pods regardless of their random naming
if [[ "$selector" =~ ^label_key= ]]; then
  target_kinds+=("pod")
fi

for kind in "${target_kinds[@]}"; do
  echo "$kind"
done

echo "--- Fetching branches (note: first 100 only)"
branches=$(curl -fsSLu "$github_token" "https://api.github.com/repos/${repo_slug}/branches?per_page=100" | jq -r ".[].name" | sed "s/.*\///")

if [[ -z "$branches" ]]; then
  echo "Could not obtain branch names from GitHub (access/credentials error?)"
  echo "No ingresses, services or deployments will be deleted"
  exit 1
fi

echo "+++ Preparing list of values to persist"
persist=$branches
if [[ -n $extra_persist_values ]]; then
  IFS="," read -ra persist_values <<<"$extra_persist_values"
  for val in "${persist_values[@]}"; do
    persist=$persist$'\n'$val
  done
fi
echo "$persist"

export KUBECONFIG=$kubeconfig_path

for kind in "${target_kinds[@]}"; do
  echo "+++ Pruning $kind..."

  if [[ "$selector" == "name" ]]; then

    # special handling for secrets: will only deal with Opaque secrets, leaving other types intact
    if [[ "$kind" == "secret" ]]; then
      all=$(./kubectl get "$kind" -n "$k8s_namespace" --field-selector=type=Opaque -o jsonpath="{.items[*].metadata.name}" | tr " " "\n" | sort)
    else
      all=$(./kubectl get "$kind" -n "$k8s_namespace" -o jsonpath="{.items[*].metadata.name}" | tr " " "\n" | sort)
    fi

    comm -13 <(echo "$persist" | sort) <(echo "$all") | while read -r name; do
      [[ -z $name ]] && continue
      [[ "$dry_run" == "1" ]] && echo "Would delete matching name: $name" && continue
      ./kubectl delete "$kind" "$name" -n "$k8s_namespace" || true
    done

  elif [[ "$selector" =~ ^label_key= ]]; then

    all=$(./kubectl get "$kind" -n "$k8s_namespace" -o jsonpath="{.items[*].metadata.labels.${selector#label_key=}}" | tr " " "\n" | sort -u)
    comm -13 <(echo "$persist" | sort) <(echo "$all") | while read -r value; do
      [[ -z $value ]] && continue
      [[ "$dry_run" == "1" ]] && echo "Would delete matching label: ${selector#label_key=}=$value" && continue
      ./kubectl delete "$kind" -n "$k8s_namespace" -l "${selector#label_key=}=$value" || true
    done

  else

    echo "Invalid selector: $selector"
    exit 1

  fi

done
