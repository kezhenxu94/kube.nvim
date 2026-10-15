#!/bin/sh
# Create the kind cluster for the end-to-end tests, with its own kubeconfig so
# that the user's kubeconfig and current context are left untouched.
set -eu

: "${KUBECONFIG:?KUBECONFIG must point to the e2e kubeconfig}"
cluster=${KIND_CLUSTER:-kube-nvim-e2e}
dir=$(dirname "$0")

if ! kind get clusters | grep -qx "$cluster"; then
  kind create cluster --name "$cluster" --wait 120s
fi

kubectl --context "kind-$cluster" apply -f "$dir/manifests.yaml"
kubectl --context "kind-$cluster" -n kube-e2e rollout status deployment/web --timeout=180s
kubectl --context "kind-$cluster" -n kube-e2e rollout status deployment/logger --timeout=180s
