#!/usr/bin/env bash
# Tears down everything created by the demo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Deleting K8s resources"
bash k8s/apply.sh delete-benchmark || true
bash k8s/apply.sh delete-rayservice || true
bash k8s/apply.sh delete-rayjob || true

echo "==> Deleting GKE cluster ${CLUSTER_NAME}"
gcloud container clusters delete "${CLUSTER_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --quiet || true

echo "==> Deleting GCS bucket gs://${BUCKET_NAME}"
gcloud storage rm -r "gs://${BUCKET_NAME}" --project="${PROJECT_ID}" --quiet || true

echo "==> Deleting Artifact Registry repo"
gcloud artifacts repositories delete "${ARTIFACT_REGISTRY}" \
  --project="${PROJECT_ID}" --location="${REGION}" --quiet || true

echo "==> Deleting GSA ${GCP_SA_EMAIL}"
gcloud iam service-accounts delete "${GCP_SA_EMAIL}" \
  --project="${PROJECT_ID}" --quiet || true

echo "==> Cleanup done"
