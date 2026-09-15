#!/usr/bin/env bash
# Bring up the control plane: minikube host cluster + Argo CD + argocd-agent principal + PKI +
# the root app-of-apps. This is the "we run this" side. Clients are added later by client-add.sh.
source "$(dirname "$0")/../scripts/lib.sh"
require_tools

AGENT_REF="${ARGOCD_AGENT_VERSION}"
KREF="https://github.com/argoproj-labs/argocd-agent/install/kubernetes"

# ------------------------------------------------------------------------------------------
log "1/6  minikube host cluster (${MINIKUBE_PROFILE})"
if minikube -p "${MINIKUBE_PROFILE}" status >/dev/null 2>&1; then
  info "profile already running"
else
  minikube start -p "${MINIKUBE_PROFILE}" \
    --cpus "${MINIKUBE_CPUS}" --memory "${MINIKUBE_MEMORY}" \
    --driver "${MINIKUBE_DRIVER}" --kubernetes-version "${MINIKUBE_K8S_VERSION}"
fi
minikube -p "${MINIKUBE_PROFILE}" addons enable ingress >/dev/null 2>&1 || warn "ingress addon not enabled"
kubectl config use-context "$(host_ctx)" >/dev/null
NODE_IP="$(minikube_ip)"
ok "host up, node IP ${NODE_IP}"

# ------------------------------------------------------------------------------------------
log "2/6  Argo CD (principal-flavoured install)"
kubectl_host create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl_host apply -f - >/dev/null
kubectl_host apply -n "${ARGOCD_NS}" --server-side \
  -k "${KREF}/argo-cd/principal?ref=${AGENT_REF}"
# apps-in-any-namespace (agents get a namespace each) + insecure UI so we can port-forward http.
# redis.server points argocd-server at the argocd-agent redis-proxy: a client app's live resource
# tree is cached in the CLIENT's redis (in their cluster), and the proxy is how the principal reads
# it. Without this, clicking a resource in the UI fails with "cache: key is missing".
kubectl_host -n "${ARGOCD_NS}" patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"application.namespaces":"*","server.insecure":"true","redis.server":"argocd-agent-redis-proxy:6379"}}'
kubectl_host -n "${ARGOCD_NS}" rollout restart deployment argocd-server >/dev/null
# Client Applications live in per-agent namespaces (apps-in-any-namespace). The default AppProject
# must allow those source namespaces or the UI refuses to open the app ("app is not allowed in
# project default") even though its status streams fine. Make the default project permissive.
kubectl_host apply -f - >/dev/null <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  description: Permissive default project for the demo (client apps live in per-agent namespaces).
  sourceNamespaces: ["*"]
  sourceRepos: ["*"]
  destinations:
    - namespace: "*"
      server: "*"
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
YAML
ok "Argo CD installed"

# ----------------------------------------------------------------------------------------
log "3/6  argocd-agent principal"
kubectl_host apply -n "${ARGOCD_NS}" -k "${KREF}/principal?ref=${AGENT_REF}"
# principal.listen.host defaults to 127.0.0.1 (loopback) in the shipped manifests, which makes the
# gRPC port unreachable from agents and the NodePort; bind 0.0.0.0 so agents can dial in. And
# allowed-namespaces=* accepts one Application namespace per agent (client-add creates one per client).
kubectl_host -n "${ARGOCD_NS}" patch configmap argocd-agent-params --type merge \
  -p '{"data":{"principal.namespace":"'"${ARGOCD_NS}"'","principal.allowed-namespaces":"*","principal.listen.host":"0.0.0.0"}}' 2>/dev/null \
  || info "argocd-agent-params not present yet (principal will use defaults)"

log "4/6  PKI + JWT (argocd-agentctl)"
CTL=(argocd-agentctl --principal-context "$(host_ctx)" --principal-namespace "${ARGOCD_NS}")
"${CTL[@]}" pki init 2>/dev/null || info "PKI already initialised"
"${CTL[@]}" jwt create-key --upsert
# Cert SANs must include the address agents dial: the minikube node IP (+ loopback for local ctl).
"${CTL[@]}" pki issue principal --ip "127.0.0.1,${NODE_IP}" --dns "localhost" --upsert
"${CTL[@]}" pki issue resource-proxy --ip "127.0.0.1,${NODE_IP}" --dns "localhost" --upsert
ok "PKI ready"

# ----------------------------------------------------------------------------------------
log "5/6  expose principal on the node (agents dial IN to us; we never dial them)"
# NodePort services so any pod (incl. inside vclusters) can reach the principal by node IP.
cat <<YAML | kubectl_host apply -f -
apiVersion: v1
kind: Service
metadata:
  name: argocd-agent-principal-node
  namespace: ${ARGOCD_NS}
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: argocd-agent-principal
  ports:
    - name: grpc
      port: 8443
      targetPort: 8443
      nodePort: ${PRINCIPAL_GRPC_NODEPORT}
    - name: resource-proxy
      port: 9090
      targetPort: 9090
      nodePort: ${RESOURCE_PROXY_NODEPORT}
YAML
# Restart so the principal picks up the patched params (notably listen.host=0.0.0.0); the pod may
# have started with the shipped default before the patch landed.
kubectl_host -n "${ARGOCD_NS}" rollout restart deploy/argocd-agent-principal >/dev/null 2>&1 || true
kubectl_host -n "${ARGOCD_NS}" rollout status deploy/argocd-agent-principal --timeout=180s || \
  warn "principal not ready yet; agents will retry"
# argocd-server was restarted in step 2 before this redis-proxy existed; restart it once more so it
# connects to the now-running proxy and can serve client resource trees in the UI.
kubectl_host -n "${ARGOCD_NS}" rollout restart deployment argocd-server >/dev/null 2>&1 || true
ok "principal reachable at ${NODE_IP}:${PRINCIPAL_GRPC_NODEPORT}"

# ------------------------------------------------------------------------------------------
log "6/6  vendor's own cloud (we own this cluster, so we just deploy it)"
case "${REPO_URL}" in
  *REPLACE_ME*) warn "REPO_URL is a placeholder. Push this repo (or set REPO_URL) so agents can pull the chart." ;;
esac
# The vendor's OWN Activepieces runs on the control-plane cluster we own: no agent, no trust
# boundary, no principal routing (that is only for clients). The principal-flavoured control plane
# has no app-controller to reconcile a local Argo CD Application, and using the agent model against
# our own cluster would be theatre, so we install it straight with Helm.
helm --kube-context "$(host_ctx)" upgrade --install ap-own-cloud "${DEMO_ROOT}/charts/activepieces-lite" \
  -n activepieces-cloud --create-namespace \
  -f "${DEMO_ROOT}/charts/activepieces-lite/values.yaml" \
  -f "${DEMO_ROOT}/charts/activepieces-lite/values.latest.yaml" \
  --set client.name=own-cloud >/dev/null
# The client fleet is onboarded imperatively (client-add: vcluster + agent + Application per client);
# gitops/applicationsets/clients.yaml is the declarative "fleet as code" alternative you graduate to.
ok "vendor's own Activepieces deploying in namespace activepieces-cloud. Clients are onboarded imperatively."

cat <<EOF

$(ok "control plane ready")
  next:  task client:spin-up          # bring up one client end-to-end (AP + a dedicated flow)
   or:   task client:add NAME=rich-client LANE=stable
   ui:   task dashboard
EOF
