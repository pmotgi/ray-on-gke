#!/usr/bin/env bash
# Source this file: `source infra/env.sh`
# Edit PROJECT_ID before sourcing.

# === EDIT THESE ===
export PROJECT_ID="northam-ce-mlai-tpu"
export REGION="us-central1"
export ZONE="us-central1-b"   # G4 / RTX PRO 6000 must be available here
# ==================

export CLUSTER_NAME="ray-gke-demo-flex"
export GKE_VERSION="1.35.3-gke.1234000"   # Min version for G4 + node-auto-provisioning

# GPU node pool config
export GPU_MACHINE_TYPE="g4-standard-48"
export GPU_TYPE="nvidia-rtx-pro-6000"
export GPU_COUNT_PER_NODE=1               # g4-standard-48 has 1× RTX PRO 6000

# GPU provisioning mode: how to acquire GPU capacity. One of:
#   on-demand  - default. Standard VMs. Predictable cost, full SLA.
#                Charged at on-demand rates. Best for stable serving.
#   spot       - --spot flag. ~60-91% discount but can be preempted at any time
#                with 30s notice. Best for fault-tolerant fine-tuning runs that
#                can resume from checkpoints. Consumes preemptible quota.
#   flex-start - --flex-start flag (Dynamic Workload Scheduler). Up to 53%
#                discount. Pool waits for capacity to come free, then runs for
#                up to 7 days. NOT preempted mid-run. Best for "I don't care
#                when it starts but I need it to finish." Consumes preemptible
#                quota. Requires GKE 1.33.0-gke.1712000+ for GPUs.
export GPU_PROVISIONING_MODE="${GPU_PROVISIONING_MODE:-on-demand}"
export GPU_POOL_NAME="gpu-pool-${GPU_PROVISIONING_MODE}"

# Storage
export BUCKET_NAME="${PROJECT_ID}-${CLUSTER_NAME}"
export ARTIFACT_REGISTRY="${CLUSTER_NAME}" #change this for your project
export AR_REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY}"

# Workload Identity
export K8S_NAMESPACE="ray-system"
export K8S_SA="ray-ksa"
export GCP_SA="ray-gcs-sa"
export GCP_SA_EMAIL="${GCP_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

# Container images
export TRAIN_IMAGE="${AR_REPO}/ray-train:latest"
export SERVE_IMAGE="${AR_REPO}/ray-serve:latest"

# Model
export BASE_MODEL="google/gemma-3-1b-it"
export FINETUNED_MODEL_NAME="gemma-3-1b-dolly"

echo "[env] PROJECT_ID=${PROJECT_ID}"
echo "[env] CLUSTER_NAME=${CLUSTER_NAME} REGION=${REGION} ZONE=${ZONE}"
echo "[env] BUCKET=${BUCKET_NAME}"
echo "[env] AR_REPO=${AR_REPO}"
echo "[env] GPU_PROVISIONING_MODE=${GPU_PROVISIONING_MODE} (pool: ${GPU_POOL_NAME})"
