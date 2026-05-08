#!/usr/bin/env bash
# Creates a GKE Standard cluster with Ray Operator + GCSFuse CSI driver and a
# small CPU node pool for the Ray head + KubeRay operator.
#
# The GPU node pool is created separately by 01b-create-gpu-nodepool.sh so that
# you can showcase three different provisioning modes (on-demand / spot /
# flex-start) without re-creating the cluster.
set -euo pipefail

: "${PROJECT_ID:?source infra/env.sh first}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "==> Creating GKE Standard cluster ${CLUSTER_NAME} in ${REGION}"

gcloud container clusters create "${CLUSTER_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --cluster-version="${GKE_VERSION}" \
  --release-channel="rapid" \
  --addons="RayOperator,GcsFuseCsiDriver" \
  --enable-ray-cluster-monitoring \
  --enable-ray-cluster-logging \
  --workload-pool="${PROJECT_ID}.svc.id.goog" \
  --machine-type="e2-standard-8" \
  --num-nodes=1 \
  --enable-autoscaling --min-nodes=1 --max-nodes=3 \
  --enable-ip-alias \
  --logging=SYSTEM,WORKLOAD \
  --cluster-ipv4-cidr=10.100.0.0/16 \
  --services-ipv4-cidr=10.101.0.0/20 \
  --monitoring=SYSTEM

echo "==> Adding Artifact Registry repo"
gcloud artifacts repositories create "${ARTIFACT_REGISTRY}" \
  --project="${PROJECT_ID}" \
  --repository-format=docker \
  --location="${REGION}" \
  --description="Ray on GKE demo images" \
  || echo "(Artifact Registry repo already exists, continuing)"

echo "==> Fetching credentials"
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --project="${PROJECT_ID}" --location="${REGION}"

echo "==> Cluster ready:"
kubectl get nodes -o wide

cat <<EOF

Next steps:
  # Create a GPU node pool. Choose ONE mode (or run multiple, each will create
  # its own pool named gpu-pool-<mode>):
  GPU_PROVISIONING_MODE=on-demand  bash infra/01b-create-gpu-nodepool.sh   # standard, predictable
  GPU_PROVISIONING_MODE=spot       bash infra/01b-create-gpu-nodepool.sh   # cheap, preemptible
  GPU_PROVISIONING_MODE=flex-start bash infra/01b-create-gpu-nodepool.sh   # cheap, queued, up-to-7-day

  bash infra/02-create-bucket.sh
  bash infra/03-setup-workload-identity.sh
  bash infra/04-hf-secret.sh
EOF
