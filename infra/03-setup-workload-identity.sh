#!/usr/bin/env bash
# Sets up Workload Identity Federation for GKE so Ray pods can read/write the
# GCS bucket via the GCSFuse CSI driver, without baking a key into the image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Creating namespace ${K8S_NAMESPACE}"
kubectl create namespace "${K8S_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating Kubernetes ServiceAccount ${K8S_SA}"
kubectl create serviceaccount "${K8S_SA}" \
  --namespace "${K8S_NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating Google ServiceAccount ${GCP_SA}"
if ! gcloud iam service-accounts describe "${GCP_SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${GCP_SA}" \
    --project="${PROJECT_ID}" \
    --display-name="Ray on GKE demo - GCS access"
fi

echo "==> Granting GSA access to bucket gs://${BUCKET_NAME}"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${GCP_SA_EMAIL}" \
  --role="roles/storage.objectUser" \
  --project="${PROJECT_ID}"

echo "==> Binding KSA -> GSA via Workload Identity"
gcloud iam service-accounts add-iam-policy-binding "${GCP_SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${K8S_NAMESPACE}/${K8S_SA}]"

echo "==> Annotating KSA"
kubectl annotate serviceaccount "${K8S_SA}" \
  --namespace "${K8S_NAMESPACE}" \
  --overwrite \
  iam.gke.io/gcp-service-account="${GCP_SA_EMAIL}"

# Allow the KSA to pull images from Artifact Registry (the GSA needs the role
# but the K8s nodes' default SA already has it via cluster default; we add it
# to be explicit so users running in shared projects don't trip up).
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${GCP_SA_EMAIL}" \
  --role="roles/artifactregistry.reader" \
  --condition=None >/dev/null

echo "==> Workload Identity wiring complete"
kubectl describe sa "${K8S_SA}" -n "${K8S_NAMESPACE}"
