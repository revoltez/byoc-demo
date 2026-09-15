#!/usr/bin/env bash
# CLIENT side. Install the vendor's agent bundle into YOUR OWN cluster. This is the whole customer
# experience: one command in their own kube-context. The agent dials OUT to the vendor's control
# plane, authenticates with the identity baked into the bundle, and starts reconciling whatever the
# vendor set as desired state. The vendor never receives a credential to this cluster.
#
#   scripts/agent-install.sh <name>
#
# In the demo the client's cluster is a vcluster, so we connect to it first to act "as the client".
# In reality the client is already in their own context and just runs the apply.
source "$(dirname "$0")/lib.sh"
need kubectl; need vcluster

NAME="${1:?usage: agent-install.sh <name>}"
NS="client-${NAME}"
CLUSTER="$(client_cluster "${NAME}")"
BUNDLE="${DEMO_ROOT}/.runtime/${NAME}-agent-bundle.yaml"
[ -f "${BUNDLE}" ] || die "no bundle for '${NAME}'. Run first:  task client:register NAME=${NAME}"

vcluster connect "${CLUSTER}" -n "${NS}" >/dev/null 2>&1 || true
VC_CTX="$(kubectl config current-context)"
kubectl config use-context "$(host_ctx)" >/dev/null 2>&1 || true

log "client '${NAME}': install the agent bundle (one command, in their cluster)"
info "\$ kubectl apply --server-side -f ${NAME}-agent-bundle.yaml"
# The bundle carries its own CRDs (Application/AppProject) plus resources that use them; a fresh
# cluster has not registered those CRDs when the first apply reaches the CRs. So: apply once to land
# the CRDs, wait for them to establish, then apply again to settle everything (a `kubectl apply -f`
# idiom for self-contained bundles). Both passes are the same file.
kubectl --context "${VC_CTX}" apply --server-side --force-conflicts -f "${BUNDLE}" 2>/dev/null || true
kubectl --context "${VC_CTX}" wait --for=condition=established --timeout=60s \
  crd/applications.argoproj.io crd/appprojects.argoproj.io >/dev/null 2>&1 || true
kubectl --context "${VC_CTX}" apply --server-side --force-conflicts -f "${BUNDLE}"
kubectl --context "${VC_CTX}" -n "${ARGOCD_NS}" rollout status deploy/argocd-agent-agent --timeout=120s \
  || warn "agent not ready yet; it will keep retrying its outbound connection"
ok "client '${NAME}' installed the agent; it is dialing the control plane outbound"
