#!/usr/bin/env bash
# VENDOR side. Register a client with the control plane and emit the agent BUNDLE the client will
# install. Runs entirely in OUR context and never touches the client's cluster: the one thing only
# we can do is mint the client's mTLS identity (a cert signed by our CA, bound to the agent name).
# Everything the client needs then travels as a single file they apply themselves.
#
#   scripts/client-register.sh <name> [lane]
#
# Output: .runtime/<name>-agent-bundle.yaml  (self-contained: minimal Argo CD + argocd-agent +
# identity + config + a default AppProject). In production this would be a signed OCI/Helm artifact
# handed over with a registration token; here it is a plain manifest, which Argo CD Agent supports.
source "$(dirname "$0")/lib.sh"
require_tools

NAME="${1:?usage: client-register.sh <name> [lane]}"
LANE="${2:-}"

CLIENT_FILE="${DEMO_ROOT}/clients/${NAME}.yaml"
if [ -z "${LANE}" ]; then
  LANE="$(yq -r '.lane // "latest"' "${CLIENT_FILE}" 2>/dev/null || echo latest)"
fi
[ -f "${CLIENT_FILE}" ] || cat > "${CLIENT_FILE}" <<YAML
name: ${NAME}
lane: ${LANE}
flags: {}
YAML

NODE_IP="$(minikube_ip)"
AGENT_REF="${ARGOCD_AGENT_VERSION}"
KREF="https://github.com/argoproj-labs/argocd-agent/install/kubernetes"
RUNTIME="${DEMO_ROOT}/.runtime"
BUNDLE="${RUNTIME}/${NAME}-agent-bundle.yaml"
ISSUE_NS="issue-${NAME}"
mkdir -p "${RUNTIME}"

# ---------------------------------------------------------------------------------------------
log "register '${NAME}': map the agent as a cluster on the principal"
kubectl_host create namespace "${NAME}" --dry-run=client -o yaml | kubectl_host apply -f - >/dev/null
# The cluster secret holds only the agent's mTLS cert and points at our own resource-proxy
# (node IP:nodeport), never a kubeconfig into the client. Idempotent: agent create errors on rerun.
if kubectl_host -n "${ARGOCD_NS}" get secret "cluster-${NAME}" >/dev/null 2>&1; then
  info "already mapped (cluster-${NAME} exists)"
else
  argocd-agentctl agent create "${NAME}" \
    --principal-context "$(host_ctx)" --principal-namespace "${ARGOCD_NS}" \
    --resource-proxy-server "${NODE_IP}:${RESOURCE_PROXY_NODEPORT}"
fi

# ---------------------------------------------------------------------------------------------
log "register '${NAME}': mint the agent's mTLS identity (on our side, signed by our CA)"
# Issue the client cert into a throwaway namespace on OUR cluster so we can read the material out
# and package it -- the client's cluster is never in the loop.
kubectl_host create namespace "${ISSUE_NS}" --dry-run=client -o yaml | kubectl_host apply -f - >/dev/null
argocd-agentctl pki issue agent "${NAME}" \
  --principal-context "$(host_ctx)" \
  --agent-context "$(host_ctx)" --agent-namespace "${ISSUE_NS}" --same-context --upsert >/dev/null
TLS_CRT="$(kubectl_host -n "${ISSUE_NS}" get secret argocd-agent-client-tls -o jsonpath='{.data.tls\.crt}')"
TLS_KEY="$(kubectl_host -n "${ISSUE_NS}" get secret argocd-agent-client-tls -o jsonpath='{.data.tls\.key}')"
CA_CRT="$(kubectl_host -n "${ISSUE_NS}" get secret argocd-agent-ca -o jsonpath='{.data.ca\.crt}')"
kubectl_host delete namespace "${ISSUE_NS}" --wait=false >/dev/null 2>&1 || true
[ -n "${TLS_CRT}" ] && [ -n "${TLS_KEY}" ] && [ -n "${CA_CRT}" ] || die "failed to mint agent identity for ${NAME}"

# ---------------------------------------------------------------------------------------------
log "register '${NAME}': package the bundle -> ${BUNDLE#${DEMO_ROOT}/}"
export NODE_IP GPORT="${PRINCIPAL_GRPC_NODEPORT}"
# Render both upstream bases through a kustomization that pins them into the argocd namespace, so the
# bundle is self-contained: the client applies it with no -n flag (kustomize skips cluster-scoped
# kinds like CRDs/ClusterRoles when stamping the namespace).
KDIR="$(mktemp -d)"
cat > "${KDIR}/kustomization.yaml" <<KZ
namespace: argocd
resources:
  - ${KREF}/argo-cd/agent-managed?ref=${AGENT_REF}
  - ${KREF}/agent?ref=${AGENT_REF}
KZ
RENDERED="$(kubectl kustomize "${KDIR}")" || die "failed to render argocd-agent manifests"
rm -rf "${KDIR}"
{
  echo "# BYOC agent bundle for '${NAME}'. The client applies this in THEIR cluster with one command."
  echo "# Contents: minimal Argo CD + argocd-agent + this client's mTLS identity + a default AppProject."
  cat <<'NS'
---
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
NS
  echo "---"
  # Everything upstream ships, minus its default params ConfigMap (we replace it below).
  printf '%s\n' "${RENDERED}" | yq eval 'select(.metadata.name != "argocd-agent-params")'
  echo "---"
  # Same ConfigMap, but with the principal address filled in so the agent dials OUT to us on boot.
  printf '%s\n' "${RENDERED}" | yq eval '
    select(.metadata.name == "argocd-agent-params")
    | .data["agent.server.address"] = strenv(NODE_IP)
    | .data["agent.server.port"] = strenv(GPORT)
    | .data["agent.mode"] = "managed"
    | .data["agent.creds"] = "mtls:any"'
  # The client's identity: CA to trust us, and its own client cert (both minted above).
  cat <<SECRETS
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-agent-ca
  namespace: argocd
type: Opaque
data:
  ca.crt: ${CA_CRT}
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-agent-client-tls
  namespace: argocd
type: kubernetes.io/tls
data:
  tls.crt: ${TLS_CRT}
  tls.key: ${TLS_KEY}
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  sourceRepos: ["*"]
  destinations:
    - namespace: "*"
      server: "*"
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
SECRETS
} > "${BUNDLE}"

# ---------------------------------------------------------------------------------------------
log "register '${NAME}': set desired state (Activepieces, lane=${LANE})"
# The Application lives in the agent's namespace on the control plane; once the agent connects the
# principal ships it down, and the client's Argo CD reconciles it locally. This is vendor-owned:
# the client controls their lane, we control what a lane resolves to.
PARAMS="$(yq -r '.flags // {} | to_entries[] | "        - name: flags." + .key + "\n          value: \"" + (.value|tostring) + "\""' "${CLIENT_FILE}")"
cat <<YAML | kubectl_host apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ap-${NAME}
  namespace: ${NAME}
  labels:
    demo/client: ${NAME}
    demo/lane: ${LANE}
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: ${REPO_REVISION}
    path: charts/activepieces-lite
    helm:
      valueFiles:
        - values.yaml
        - values.${LANE}.yaml
      parameters:
        - name: client.name
          value: ${NAME}
${PARAMS}
  destination:
    server: https://kubernetes.default.svc
    namespace: activepieces
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

ok "registered '${NAME}'. Hand them:  ${BUNDLE#${DEMO_ROOT}/}"
info "they install it with:  task client:install-agent NAME=${NAME}"
