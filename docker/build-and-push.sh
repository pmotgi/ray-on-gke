#!/usr/bin/env bash
# Build train + serve images and push to Artifact Registry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
source infra/env.sh

echo "==> Configuring Docker auth for ${REGION}-docker.pkg.dev"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

echo "==> Building TRAIN image: ${TRAIN_IMAGE}"
docker build -f docker/Dockerfile.train -t "${TRAIN_IMAGE}" .

echo "==> Building SERVE image: ${SERVE_IMAGE}"
docker build -f docker/Dockerfile.serve -t "${SERVE_IMAGE}" .

echo "==> Pushing"
docker push "${TRAIN_IMAGE}"
docker push "${SERVE_IMAGE}"

echo "==> Done"
echo "    TRAIN_IMAGE=${TRAIN_IMAGE}"
echo "    SERVE_IMAGE=${SERVE_IMAGE}"
