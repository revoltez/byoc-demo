#!/usr/bin/env bash
# Best-effort: give a client's Activepieces a first admin user and a dedicated demo flow, via the
# public REST API, so the client gets a working automation and not just a running pod.
# Tolerant by design: if the API shape differs on a given lane, it logs and moves on.
#
#   scripts/seed-flow.sh <name>
#
source "$(dirname "$0")/lib.sh"
need kubectl; need jq; need vcluster
NAME="${1:?usage: seed-flow.sh <name>}"
NS="client-${NAME}"
CLUSTER="$(client_cluster "${NAME}")"

EMAIL="admin@${NAME}.demo"
PASSWORD="Activepieces123!"
PORT="${AP_LOCAL_PORT:-8080}"

log "seed-flow: reaching ${NAME}'s Activepieces"
vcluster connect "${CLUSTER}" -n "${NS}" >/dev/null 2>&1 || true
VC_CTX="$(kubectl config current-context)"
kubectl config use-context "$(host_ctx)" >/dev/null 2>&1 || true

# Port-forward into the client's own cluster (through the vcluster API). No inbound to the client.
kubectl --context "${VC_CTX}" -n activepieces port-forward "svc/ap-${NAME}" "${PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT
BASE="http://localhost:${PORT}/api/v1"

info "waiting for the app to answer ..."
for _ in $(seq 1 60); do
  if curl -fsS "${BASE}/flags" >/dev/null 2>&1; then break; fi
  sleep 3
done
curl -fsS "${BASE}/flags" >/dev/null 2>&1 || { warn "app not responding yet; skipping seed"; exit 0; }

log "seed-flow: create the first admin user"
SIGNUP="$(curl -fsS -X POST "${BASE}/authentication/sign-up" \
  -H 'content-type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"firstName\":\"Demo\",\"lastName\":\"Admin\",\"trackEvents\":false,\"newsLetter\":false}" \
  2>/dev/null || true)"
TOKEN="$(echo "${SIGNUP}" | jq -r '.token // empty' 2>/dev/null || true)"
PROJECT_ID="$(echo "${SIGNUP}" | jq -r '.projectId // empty' 2>/dev/null || true)"

if [ -z "${TOKEN}" ]; then
  warn "sign-up did not return a token (maybe a user already exists). Skipping flow creation."
  info "log in at http://localhost:${PORT} as ${EMAIL} / ${PASSWORD}"
  exit 0
fi

log "seed-flow: create a dedicated flow for ${NAME}"
FLOW="$(curl -fsS -X POST "${BASE}/flows" \
  -H "authorization: Bearer ${TOKEN}" -H 'content-type: application/json' \
  -d "{\"displayName\":\"${NAME} onboarding (demo)\",\"projectId\":\"${PROJECT_ID}\"}" \
  2>/dev/null || true)"
FLOW_ID="$(echo "${FLOW}" | jq -r '.id // empty' 2>/dev/null || true)"

if [ -n "${FLOW_ID}" ]; then
  ok "flow '${NAME} onboarding (demo)' created (${FLOW_ID})"
else
  warn "flow creation returned nothing usable; the admin user still exists"
fi
cat <<EOF

$(ok "client '${NAME}' is a real, working Activepieces")
  URL:   http://localhost:${PORT}   (keep 'task client:open NAME=${NAME}' running)
  login: ${EMAIL} / ${PASSWORD}
EOF
