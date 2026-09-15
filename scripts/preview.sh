#!/usr/bin/env bash
# Open or close an ephemeral PR-preview Activepieces on the control-plane cluster.
#   scripts/preview.sh open  <pr-number>
#   scripts/preview.sh close <pr-number>
#
# Previews run on the cluster WE own, so there is no agent and no trust boundary: we just deploy the
# chart directly with Helm (the principal-flavoured control plane has no app-controller to reconcile
# a local Argo CD Application). We also write previews/pr-<n>.yaml to illustrate the gitops input a
# real `pullRequest` generator would consume (see gitops/applicationsets/pr-previews.yaml).
source "$(dirname "$0")/lib.sh"
require_tools
ACTION="${1:?usage: preview.sh <open|close> <pr-number>}"
PR="${2:?usage: preview.sh <open|close> <pr-number>}"
FILE="${DEMO_ROOT}/previews/pr-${PR}.yaml"
REL="preview-${PR}"
NS="preview-${PR}"

case "${ACTION}" in
  open)
    mkdir -p "${DEMO_ROOT}/previews"
    printf 'number: "%s"\n' "${PR}" > "${FILE}"   # the gitops input a pullRequest generator would emit
    log "opening preview for PR #${PR}"
    helm --kube-context "$(host_ctx)" upgrade --install "${REL}" "${DEMO_ROOT}/charts/activepieces-lite" \
      -n "${NS}" --create-namespace \
      -f "${DEMO_ROOT}/charts/activepieces-lite/values.yaml" \
      -f "${DEMO_ROOT}/charts/activepieces-lite/values.latest.yaml" \
      --set "client.name=pr-${PR}" \
      --set "persistence.enabled=false" >/dev/null
    ok "preview-${PR} deploying (namespace ${NS}). Ephemeral: no persistence."
    ;;
  close)
    log "closing preview for PR #${PR}"
    rm -f "${FILE}"
    helm --kube-context "$(host_ctx)" uninstall "${REL}" -n "${NS}" >/dev/null 2>&1 || true
    kubectl_host delete namespace "${NS}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    ok "preview-${PR} pruned"
    ;;
  *) die "unknown action '${ACTION}' (open|close)";;
esac
