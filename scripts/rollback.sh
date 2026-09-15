#!/usr/bin/env bash
# Roll a client back to a known-good lane (default: stable). Same mechanism as lane-set; named
# separately because "roll it back" is the sentence you say in the room.
#   scripts/rollback.sh <name> [lane=stable]
source "$(dirname "$0")/lib.sh"
NAME="${1:?usage: rollback.sh <name> [lane]}"
LANE="${2:-stable}"
log "rolling ${NAME} back to ${LANE}"
exec "${DEMO_ROOT}/scripts/lane-set.sh" "${NAME}" "${LANE}"
