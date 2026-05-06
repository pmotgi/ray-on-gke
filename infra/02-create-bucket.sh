#!/usr/bin/env bash
# Creates a regional GCS bucket for checkpoints, datasets, benchmark outputs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Creating GCS bucket gs://${BUCKET_NAME}"

if gcloud storage buckets describe "gs://${BUCKET_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "(Bucket already exists)"
else
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --default-storage-class=STANDARD
fi

# Pre-create the directory layout (GCS uses object prefixes; we create marker objects)
echo "==> Initialising bucket layout"
for prefix in datasets checkpoints benchmark-results; do
  echo "" | gcloud storage cp - "gs://${BUCKET_NAME}/${prefix}/.keep" \
    --project="${PROJECT_ID}" >/dev/null
done

gcloud storage ls "gs://${BUCKET_NAME}/"

echo "==> Bucket ready"
