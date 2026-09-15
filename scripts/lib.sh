#!/usr/bin/env bash
# Shared helpers. Every script does:  source "$(dirname "$0")/lib.sh"
set -euo pipefail

# Repo root = parent of scripts/ (or of deploy/). Resolve regardless of caller CWD.
DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEMO_ROOT

# shellcheck source=/dev/null
source "${DEMO_ROOT}/demo.env"

# --- pretty logging -----------------------------------------------------------------------
_c() { printf '\033[%sm' "$1"; }
log()  { printf '%s▸ %s%s\n' "$(_c '1;35')" "$*" "$(_c 0)"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '%s! %s%s\n' "$(_c '1;33')" "$*" "$(_c 0)" >&2; }
die()  { printf '%s✗ %s%s\n' "$(_c '1;31')" "$*" "$(_c 0)" >&2; exit 1; }
ok()   { printf '%s✓ %s%s\n' "$(_c '1;32')" "$*" "$(_c 0)"; }

# --- context helpers ----------------------------------------------------------------------
host_ctx() { echo "${MINIKUBE_PROFILE}"; }            # minikube sets the context = profile name
client_cluster() { echo "$1-cluster"; }               # a client's vcluster name, e.g. rich-client-cluster
vc_ctx()   { echo "vcluster_$(client_cluster "$1")_client-$1_${MINIKUBE_PROFILE}"; }  # vcluster connect context name

kubectl_host() { kubectl --context "$(host_ctx)" "$@"; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1 (are you in 'nix develop' / direnv?)"; }

require_tools() {
  for t in minikube kubectl helm vcluster argocd argocd-agentctl jq yq; do need "$t"; done
}

# Minikube node IP: the address agents dial to reach the principal. Reachable from every pod.
minikube_ip() { minikube -p "${MINIKUBE_PROFILE}" ip; }

# Wait for a rollout/condition without hanging forever.
wait_rollout() { # <context> <namespace> <deploy>
  kubectl --context "$1" -n "$2" rollout status "deploy/$3" --timeout=180s
}
