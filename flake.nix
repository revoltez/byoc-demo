{
  description = "byoc-demo: ArgoCD + argocd-agent + vcluster demo for Activepieces";

  # Single input on purpose: fewer moving parts, faster cold clone. Multi-system is
  # hand-rolled below instead of pulling in flake-utils.
  # Pinned to a concrete nixos-26.05 commit: fetch-by-rev goes through codeload, so it never
  # touches the rate-limited github API. `nix flake update` bumps it when you want a newer pin.
  inputs.nixpkgs.url = "github:nixos/nixpkgs/21a67dc470149f337cecafbe965d8d252a390518";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

    # argocd-agentctl is not in nixpkgs, so fetch the pinned release binary.
    # Version + hashes come from the release's *_checksums.txt asset:
    #   https://github.com/argoproj-labs/argocd-agent/releases/tag/vX.Y.Z
    #   (convert each sha256 to SRI with `nix hash convert --hash-algo sha256 --to sri`)
    argocdAgentVersion = "0.10.0";
    argocdAgentctl = {
      hash = {
        "x86_64-linux" = "sha256-/VJ0UKLoy/VE8zTWfrY9g6STyhkYK1BanMsMpqGg7hs=";
        "aarch64-linux" = "sha256-Fk95Vk9BtZ54j/uj5u+hwNmC/vxj7kG3T4w3q+mFPok=";
        "x86_64-darwin" = "sha256-h2Dhfg1E0fGdOpCfWVHmYdHTFI5Fk9GneTiqLk7GITk=";
        "aarch64-darwin" = "sha256-xc0erl8PsVIcfO1h3VS84FzFngKOzbs9exfqiS0jC3k=";
      };
      asset = {
        "x86_64-linux" = "argocd-agentctl-linux-amd64";
        "aarch64-linux" = "argocd-agentctl-linux-arm64";
        "x86_64-darwin" = "argocd-agentctl-darwin-amd64";
        "aarch64-darwin" = "argocd-agentctl-darwin-arm64";
      };
    };

    mkAgentctl = pkgs: system:
      pkgs.stdenvNoCC.mkDerivation {
        pname = "argocd-agentctl";
        version = argocdAgentVersion;
        src = pkgs.fetchurl {
          url = "https://github.com/argoproj-labs/argocd-agent/releases/download/v${argocdAgentVersion}/${argocdAgentctl.asset.${system}}";
          hash = argocdAgentctl.hash.${system};
        };
        dontUnpack = true;
        installPhase = "install -Dm755 $src $out/bin/argocd-agentctl";
        meta.description = "CLI for argocd-agent (pinned release binary)";
      };
  in {
    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        name = "byoc-demo";
        buildInputs =
          (with pkgs; [
            # cluster + gitops toolchain
            minikube # local Kubernetes (host / control-plane cluster)
            vcluster # virtual clusters = the "clients"
            kubernetes-helm # helm
            kubectl
            kubectx # kubectx / kubens
            argocd # argocd CLI
            k9s # TUI for eyeballing the cluster
            # scripting helpers
            go-task # `task` runner
            jq
            yq-go # `yq`
            openssl # demo secret generation
            curl
            coreutils
          ])
          ++ [(mkAgentctl pkgs system)];
        shellHook = ''
          export KUBECONFIG="$PWD/.kube/config"
          mkdir -p "$PWD/.kube"
          echo "byoc-demo devshell"
          echo "  argocd-agentctl ${argocdAgentVersion} | minikube / vcluster / argocd / helm / task pinned"
          echo "  KUBECONFIG=$KUBECONFIG"
          echo "  run 'task' to see available targets"
        '';
      };
    });
  };
}
