#!/usr/bin/env bash
# Creates a GPU node pool on the existing GKE cluster.
#
# Switchable via env var GPU_PROVISIONING_MODE (set in infra/env.sh, or
# override per-invocation):
#
#   on-demand   : Standard VMs. Predictable cost, full SLA, no preemption.
#                 Charged at on-demand rates (~$3.50/hr for g4-standard-48 in
#                 us-central1; check current pricing).
#                 Best for: stable serving (Ray Serve / RayService).
#
#   spot        : --spot flag. ~60-91% discount but VMs can be reclaimed at any
#                 time with 30s notice. Consumes preemptible quota.
#                 Best for: fault-tolerant fine-tuning that checkpoints to GCS
#                 and can resume mid-run.
#
#   flex-start  : --flex-start flag (Dynamic Workload Scheduler). ~53% discount
#                 on vCPU/GPU. The pool waits for capacity, then runs nodes for
#                 up to 7 days WITHOUT preemption. Consumes preemptible quota.
#                 Requires GKE 1.33.0-gke.1712000+ for GPUs.
#                 Best for: "I don't care when it starts but I need it to
#                 finish without interruption" — i.e. a 4-hour fine-tuning run.
#
# Each mode produces a distinct node pool (gpu-pool-on-demand,
# gpu-pool-spot, gpu-pool-flex-start) so you can demo all three side-by-side.
# The Ray pods select a pool via nodeSelector; see
# k8s/rayjob-finetune.yaml and k8s/rayservice-gemma.yaml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

MODE="${GPU_PROVISIONING_MODE}"
POOL="${GPU_POOL_NAME}"

echo "==> Creating GPU node pool '${POOL}' in mode '${MODE}'"
echo "    machine: ${GPU_MACHINE_TYPE}, GPU: ${GPU_TYPE} x${GPU_COUNT_PER_NODE}"

# Common flags shared across all three modes.
COMMON_FLAGS=(
  --project="${PROJECT_ID}"
  --cluster="${CLUSTER_NAME}"
  --location="${REGION}"
  --node-locations="${ZONE}"
  --machine-type="${GPU_MACHINE_TYPE}"
  --accelerator="type=${GPU_TYPE},count=${GPU_COUNT_PER_NODE},gpu-driver-version=default"
  --disk-size=200
  --ephemeral-storage-local-ssd count=4
  # Taint so that only Ray GPU workloads land on these nodes.
  --node-taints="nvidia.com/gpu=present:NoSchedule"
)

# Mode-specific flags + labels. The labels are how the workloads opt into a
# specific pool via nodeSelector.
case "${MODE}" in
  on-demand)
    MODE_FLAGS=(
      --num-nodes=0
      --enable-autoscaling --min-nodes=0 --max-nodes=2
      --node-labels="ray-gke-demo/gpu=true,ray-gke-demo/provisioning=on-demand"
    )
    ;;

  spot)
    MODE_FLAGS=(
      --spot
      --num-nodes=0
      --enable-autoscaling --min-nodes=0 --max-nodes=4
      --node-labels="ray-gke-demo/gpu=true,ray-gke-demo/provisioning=spot"
    )
    ;;

  flex-start)
    # flex-start requires:
    #   * --num-nodes=0 (DWS provisions on demand)
    #   * --location-policy=ANY for best-effort placement
    #   * --reservation-affinity=none (don't try to consume a reservation)
    #   * --no-enable-autorepair (autorepair is incompatible)
    MODE_FLAGS=(
      --flex-start
      --num-nodes=0
      --enable-autoscaling --min-nodes=0 --max-nodes=4
      --location-policy=ANY
      --reservation-affinity=none
      --no-enable-autorepair
      --node-labels="ray-gke-demo/gpu=true,ray-gke-demo/provisioning=flex-start"
    )
    ;;

  *)
    echo "ERROR: GPU_PROVISIONING_MODE must be one of: on-demand, spot, flex-start" >&2
    echo "       Got: '${MODE}'" >&2
    exit 1
    ;;
esac

gcloud container node-pools create "${POOL}" \
  "${COMMON_FLAGS[@]}" \
  "${MODE_FLAGS[@]}"

echo
echo "==> Done. Inspect with:"
echo "    gcloud container node-pools describe ${POOL} --cluster=${CLUSTER_NAME} --location=${REGION}"
echo
echo "==> To target this pool from a Ray pod, use this nodeSelector:"
echo "    cloud.google.com/gke-accelerator: ${GPU_TYPE}"
echo "    ray-gke-demo/provisioning: ${MODE}"
