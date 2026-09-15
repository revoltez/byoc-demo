#!/usr/bin/env bash
# Port-forward the Argo CD UI and print the admin login. This is the "chaos becomes a screen"
# payoff: every client, its lane, health and drift, in one place.
source "$(dirname "$0")/lib.sh"
need kubectl
PORT="${ARGOCD_LOCAL_PORT:-8081}"
PW="$(kubectl_host -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
cat <<EOF
$(ok "Argo CD UI")
  URL:   http://localhost:${PORT}    (plain HTTP: bootstrap runs argocd-server insecure for local use)
  login: admin / ${PW:-<run: kubectl -n argocd get secret argocd-initial-admin-secret>}
  Ctrl-C to stop.
EOF
exec kubectl --context "$(host_ctx)" -n "${ARGOCD_NS}" port-forward svc/argocd-server "${PORT}:443"
