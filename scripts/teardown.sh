#!/usr/bin/env bash
# Tear everything down: delete client vclusters, the minikube host cluster, and the demo PKI.
source "$(dirname "$0")/lib.sh"
need minikube; need vcluster

log "deleting client vclusters"
if minikube -p "${MINIKUBE_PROFILE}" status >/dev/null 2>&1; then
  kubectl config use-context "$(host_ctx)" >/dev/null 2>&1 || true
  for ns in $(kubectl_host get ns -o name 2>/dev/null | sed 's#namespace/##' | grep '^client-' || true); do
    name="${ns#client-}"
    vcluster delete "$(client_cluster "${name}")" -n "${ns}" 2>/dev/null || true
  done
fi

log "deleting minikube host cluster '${MINIKUBE_PROFILE}'"
minikube delete -p "${MINIKUBE_PROFILE}" || true

log "removing local kubeconfig + PKI"
rm -rf "${DEMO_ROOT}/.kube" "${DEMO_ROOT}/pki" 2>/dev/null || true
ok "clean"
