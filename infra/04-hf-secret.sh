#!/usr/bin/env bash
# Stores the HuggingFace token as a K8s Secret so pods can pull gated models
# (Gemma 3 1B requires accepting the license and using a valid HF token).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

if [[ -z "${HF_TOKEN:-}" ]]; then
  echo "Paste your HuggingFace token (with read access to google/gemma-3-1b-it)."
  echo "Create one at: https://huggingface.co/settings/tokens"
  read -rsp "HF_TOKEN: " HF_TOKEN
  echo
fi

if [[ -z "${HF_TOKEN}" ]]; then
  echo "ERROR: HF_TOKEN is empty" >&2
  exit 1
fi

kubectl create secret generic hf-token \
  --namespace "${K8S_NAMESPACE}" \
  --from-literal=HUGGING_FACE_HUB_TOKEN="${HF_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Secret 'hf-token' stored in namespace ${K8S_NAMESPACE}"
