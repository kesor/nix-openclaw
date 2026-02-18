# ═══════════════════════════════════════════════════════════════════════════════
# File: flake.nix
# ═══════════════════════════════════════════════════════════════════════════════
{
  description = "NixOS and Home-Manager module for deploying OpenClaw securely";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # OpenClaw application source — override this in your consumer flake.
    #
    #   inputs.nix-openclaw.inputs.openclaw-src.url = "github:you/openclaw";
    #   inputs.nix-openclaw.inputs.openclaw-src.url = "git+ssh://git@github.com/you/private-repo";
    #   inputs.nix-openclaw.inputs.openclaw-src.url = "path:/path/to/openclaw";
    #
    openclaw-src = {
      url = "github:openclaw/openclaw";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      openclaw-src,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        fn:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          fn {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );
    in
    {
      # ── Overlay ────────────────────────────────────────────────────────────────
      overlays.default = final: _prev: {
        openclaw = final.callPackage ./package.nix { src = openclaw-src; };
      };

      # ── Packages ───────────────────────────────────────────────────────────────
      packages = forAllSystems (
        { pkgs, ... }:
        rec {
          openclaw = pkgs.callPackage ./package.nix { src = openclaw-src; };
          default = openclaw;
        }
      );

      # ── NixOS Module ──────────────────────────────────────────────────────────
      nixosModules = rec {
        openclaw = import ./modules/nixos.nix self;
        default = openclaw;
      };

      # ── Home-Manager Module ───────────────────────────────────────────────────
      homeManagerModules = rec {
        openclaw = import ./modules/home-manager.nix self;
        default = openclaw;
      };

      # ── Dev Shell (for working on this repo itself) ───────────────────────────
      devShells = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nodejs_22
              nil
              nixfmt-rfc-style
              git
            ];
          };
        }
      );
    };
}
