#!/usr/bin/env bash
# Onboard one client, end to end, as the three honest steps it really is:
#   1. the client stands up their own cluster            (client-cluster.sh)
#   2. WE register them and mint an install bundle       (client-register.sh -- vendor side)
#   3. the CLIENT installs that bundle themselves         (agent-install.sh -- one command)
# No vendor credential ever reaches the client's cluster; the client opens the connection to us.
#
#   scripts/client-add.sh <name> [lane]
source "$(dirname "$0")/lib.sh"
require_tools

NAME="${1:?usage: client-add.sh <name> [lane]}"
LANE="${2:-}"
D="${DEMO_ROOT}/scripts"

bash "${D}/client-cluster.sh"  "${NAME}"            # the client's own cluster
bash "${D}/client-register.sh" "${NAME}" "${LANE}"  # vendor: mapping + identity + bundle + desired state
bash "${D}/agent-install.sh"   "${NAME}"            # client: one command, dials out

NODE_IP="$(minikube_ip)"
ok "client '${NAME}' onboarded. It is dialing ${NODE_IP}:${PRINCIPAL_GRPC_NODEPORT} outbound."
info "watch it appear:  task dashboard   (as destination cluster '${NAME}')"
