#!/usr/bin/env bash
# Move a client to another version lane. Updates the desired state (clients/<name>.yaml) and the
# live Application; Argo CD rolls the image. This is the finite-lanes story, one command.
#   scripts/lane-set.sh <name> <latest|stable|lts>
source "$(dirname "$0")/lib.sh"
require_tools
NAME="${1:?usage: lane-set.sh <name> <lane>}"
LANE="${2:?usage: lane-set.sh <name> <lane>}"
lane_to_tag "${LANE}" >/dev/null  # validate

CLIENT_FILE="${DEMO_ROOT}/clients/${NAME}.yaml"
if [ -f "${CLIENT_FILE}" ]; then
  yq -i ".lane = \"${LANE}\"" "${CLIENT_FILE}"
  info "updated desired state ${CLIENT_FILE} (commit + push for the git path)"
fi

log "moving ${NAME} to '${LANE}' (image $(lane_to_tag "${LANE}"))"
kubectl_host -n "${NAME}" patch application "ap-${NAME}" --type merge -p "$(cat <<JSON
{"metadata":{"labels":{"demo/lane":"${LANE}"}},"spec":{"source":{"helm":{"valueFiles":["values.yaml","values.${LANE}.yaml"]}}}}
JSON
)"
ok "${NAME} set to ${LANE}. Watch it roll:  task dashboard"
