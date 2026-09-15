#!/usr/bin/env bash
# Stand up the CLIENT's own cluster. In the demo this is a vcluster on the control-plane node so you
# can watch a fleet at once; in reality the client already has a real cluster (EKS/GKE/AKS/on-prem)
# and this step is just "they have somewhere to run it". Nothing here belongs to the vendor.
#   scripts/client-cluster.sh <name>
source "$(dirname "$0")/lib.sh"
need vcluster; need kubectl

NAME="${1:?usage: client-cluster.sh <name>}"
NS="client-${NAME}"
CLUSTER="$(client_cluster "${NAME}")"

log "client '${NAME}': stand up their cluster (${CLUSTER})"
if vcluster list --output json 2>/dev/null | jq -e --arg n "${CLUSTER}" '.[]?|select(.Name==$n)' >/dev/null; then
  info "vcluster already exists"
else
  vcluster create "${CLUSTER}" -n "${NS}" --connect=false
fi
vcluster connect "${CLUSTER}" -n "${NS}"          # switches current-context to the vcluster
info "client kube-context: $(kubectl config current-context)"
kubectl config use-context "$(host_ctx)" >/dev/null
ok "client '${NAME}' has a cluster"
