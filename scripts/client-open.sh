#!/usr/bin/env bash
# Open a client's Activepieces UI by port-forwarding into its own cluster. Blocks until Ctrl-C.
#   scripts/client-open.sh <name>
source "$(dirname "$0")/lib.sh"
need kubectl; need vcluster
NAME="${1:?usage: client-open.sh <name>}"
NS="client-${NAME}"
CLUSTER="$(client_cluster "${NAME}")"
PORT="${AP_LOCAL_PORT:-8080}"

vcluster connect "${CLUSTER}" -n "${NS}" >/dev/null 2>&1 || true
VC_CTX="$(kubectl config current-context)"
kubectl config use-context "$(host_ctx)" >/dev/null 2>&1 || true

ok "http://localhost:${PORT}  (Ctrl-C to stop)"
exec kubectl --context "${VC_CTX}" -n activepieces port-forward "svc/ap-${NAME}" "${PORT}:80"
