#!/usr/bin/env bash
# Convenience wrapper. Applies the benchmark pod and tails its logs.
#
# This calls `vllm bench serve` from inside the cluster, hitting the in-cluster
# Ray Serve service. It writes results (JSON) to gs://<BUCKET>/benchmark-results/.
#
# Reads more like a recipe than a tool — the heavy lifting is in
# k8s/benchmark-pod.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
source infra/env.sh

# Apply with envsubst so the manifest's REGION / PROJECT_ID / BUCKET_NAME
# placeholders resolve.
envsubst '${REGION} ${PROJECT_ID} ${BUCKET_NAME}' < k8s/benchmark-pod.yaml \
  | kubectl apply -f -

echo "==> Waiting for benchmark pod to start"
kubectl wait --for=condition=Ready pod/vllm-benchmark -n "${K8S_NAMESPACE}" --timeout=10m || true

echo "==> Streaming logs (ctrl-c to detach; pod will keep running)"
kubectl logs -f vllm-benchmark -n "${K8S_NAMESPACE}"

echo
echo "==> Results JSON saved to gs://${BUCKET_NAME}/benchmark-results/"
gcloud storage ls "gs://${BUCKET_NAME}/benchmark-results/" --project="${PROJECT_ID}"
