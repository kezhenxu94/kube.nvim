#!/bin/sh
# Create the kind cluster of the demo, with its own kubeconfig so that the
# user's kubeconfig and current context are left untouched.
set -eu

dir=$(cd "$(dirname "$0")" && pwd)
export KUBECONFIG="$dir/.kubeconfig"
cluster=kube-nvim-demo

if ! kind get clusters | grep -qx "$cluster"; then
  kind create cluster --name "$cluster" --wait 120s
fi

kubectl apply -f "$dir/manifests.yaml"
for deployment in web api; do
  kubectl -n demo rollout status "deployment/$deployment" --timeout=180s
done

# A Helm release with two revisions, for its history and rollback
helm uninstall storefront -n demo --ignore-not-found --wait
helm install storefront "$dir/chart" -n demo
helm upgrade storefront "$dir/chart" -n demo --set theme=dark
