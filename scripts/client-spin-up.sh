#!/usr/bin/env bash
# The headline "how easy is it" demo: one client, end to end. Create the client's cluster,
# onboard it via argocd-agent (outbound), wait for Activepieces to land, then seed a dedicated
# flow so it is a working automation, not just a pod.
#
#   scripts/client-spin-up.sh [name] [lane]
#
source "$(dirname "$0")/lib.sh"
NAME="${1:-rich-client}"
LANE="${2:-stable}"

log "spin-up '${NAME}' (${LANE} lane) end to end"
"${DEMO_ROOT}/scripts/client-add.sh" "${NAME}" "${LANE}"

log "waiting for Activepieces to sync into ${NAME}'s cluster"
NS="client-${NAME}"
CLUSTER="$(client_cluster "${NAME}")"
vcluster connect "${CLUSTER}" -n "${NS}" >/dev/null 2>&1 || true
VC_CTX="$(kubectl config current-context)"
kubectl config use-context "$(host_ctx)" >/dev/null 2>&1 || true

# Cold start is a chain: agent connects -> principal ships the Application -> the client's Argo CD
# renders the chart -> the image is pulled. On a fresh cluster the in-cluster repo-server may not be
# up when the app-controller first tries, and its own retry is slow, so we nudge a refresh and poll
# for the Deployment to exist before waiting on its rollout (rollout status errors immediately if the
# Deployment/namespace is not there yet, which is why a plain wait gives up instantly).
deadline=$(( $(date +%s) + ${AP_WAIT_SECONDS:-600} ))
ready=false
while [ "$(date +%s)" -lt "${deadline}" ]; do
  kubectl --context "${VC_CTX}" -n argocd annotate application "ap-${NAME}" \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
  if kubectl --context "${VC_CTX}" -n activepieces get "deploy/ap-${NAME}" >/dev/null 2>&1 \
     && kubectl --context "${VC_CTX}" -n activepieces rollout status "deploy/ap-${NAME}" --timeout=30s >/dev/null 2>&1; then
    ready=true; break
  fi
  sleep 10
done
if "${ready}"; then
  ok "Activepieces is running in ${NAME}'s cluster"
else
  warn "Activepieces not ready within timeout; the agent will keep reconciling. Try seed later:"
  info "  task client:seed NAME=${NAME}"
  exit 0
fi

"${DEMO_ROOT}/scripts/seed-flow.sh" "${NAME}"
