#!/usr/bin/env bash
# Helper to substitute placeholders into the K8s manifests and apply them.
#
# Substitutions:
#   REGION-docker.pkg.dev/PROJECT_ID -> ${REGION}-docker.pkg.dev/${PROJECT_ID}
#   bucketName: BUCKET_NAME          -> bucketName: ${BUCKET_NAME}
#   gs://BUCKET_NAME                 -> gs://${BUCKET_NAME}
#   TRAIN_PROVISIONING_MODE          -> ${TRAIN_PROVISIONING_MODE} (default: spot)
#   SERVE_PROVISIONING_MODE          -> ${SERVE_PROVISIONING_MODE} (default: on-demand)
#
# Usage:
#   bash k8s/apply.sh rayjob       # apply the fine-tuning RayJob
#   bash k8s/apply.sh rayservice   # apply the Ray Serve RayService
#   bash k8s/apply.sh benchmark    # apply the benchmark pod
#   bash k8s/apply.sh delete-rayjob
#   bash k8s/apply.sh delete-rayservice
#   bash k8s/apply.sh delete-benchmark
#
# Override which GPU pool a workload lands on:
#   TRAIN_PROVISIONING_MODE=flex-start bash k8s/apply.sh rayjob
#   SERVE_PROVISIONING_MODE=on-demand  bash k8s/apply.sh rayservice
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
source infra/env.sh

# Defaults: fine-tuning is fault-tolerant -> spot is cheapest sensible choice.
# Serving needs predictable latency -> on-demand. Override via env if you want.
: "${TRAIN_PROVISIONING_MODE:=spot}"
: "${SERVE_PROVISIONING_MODE:=on-demand}"

substitute() {
  sed -e "s|REGION-docker.pkg.dev/PROJECT_ID|${REGION}-docker.pkg.dev/${PROJECT_ID}|g" \
      -e "s|bucketName: BUCKET_NAME|bucketName: ${BUCKET_NAME}|g" \
      -e "s|gs://BUCKET_NAME|gs://${BUCKET_NAME}|g" \
      -e "s|TRAIN_PROVISIONING_MODE|${TRAIN_PROVISIONING_MODE}|g" \
      -e "s|SERVE_PROVISIONING_MODE|${SERVE_PROVISIONING_MODE}|g" \
      "$1"
}

case "${1:-}" in
  rayjob)
    echo "==> Applying RayJob (training will land on pool gpu-pool-${TRAIN_PROVISIONING_MODE})"
    substitute k8s/rayjob-finetune.yaml | kubectl apply -f -
    ;;
  rayservice)
    echo "==> Applying RayService (serving will land on pool gpu-pool-${SERVE_PROVISIONING_MODE})"
    substitute k8s/rayservice-gemma.yaml | kubectl apply -f -
    ;;
  benchmark)
    substitute k8s/benchmark-pod.yaml | kubectl apply -f -
    ;;
  delete-rayjob)
    substitute k8s/rayjob-finetune.yaml | kubectl delete --ignore-not-found -f -
    ;;
  delete-rayservice)
    substitute k8s/rayservice-gemma.yaml | kubectl delete --ignore-not-found -f -
    ;;
  delete-benchmark)
    substitute k8s/benchmark-pod.yaml | kubectl delete --ignore-not-found -f -
    ;;
  *)
    echo "Usage: $0 {rayjob|rayservice|benchmark|delete-rayjob|delete-rayservice|delete-benchmark}"
    exit 1
    ;;
esac
