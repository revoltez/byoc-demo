#!/usr/bin/env bash
# Show self-heal: scale a client's Activepieces to 0 behind Argo CD's back, then watch it get put
# back. Drift stops being a feeling and becomes a screen.
#   scripts/drift.sh <name>
source "$(dirname "$0")/lib.sh"
need kubectl; need vcluster
NAME="${1:?usage: drift.sh <name>}"
NS="client-${NAME}"
CLUSTER="$(client_cluster "${NAME}")"
vcluster connect "${CLUSTER}" -n "${NS}" >/dev/null 2>&1 || true
VC_CTX="$(kubectl config current-context)"
kubectl config use-context "$(host_ctx)" >/dev/null 2>&1 || true

log "introducing drift: scaling ap-${NAME} to 0 replicas in the client's cluster"
kubectl --context "${VC_CTX}" -n activepieces scale "deploy/ap-${NAME}" --replicas=0
info "open 'task dashboard' now: ap-${NAME} goes OutOfSync, then Argo CD self-heals it back to 1."
