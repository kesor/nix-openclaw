# ═══════════════════════════════════════════════════════════════════════════════
# File: flake.nix
# Description: Flake entry point for nix-openclaw using flake-parts.
# ═══════════════════════════════════════════════════════════════════════════════
{
  description = "NixOS and Home-Manager module for deploying OpenClaw securely";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    openclaw-src = {
      url = "github:openclaw/openclaw";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Build package with optional pnpmDepsHash override
      mkOpenclawPackage =
        system: pnpmDepsHash:
        (nixpkgs.legacyPackages.${system}).callPackage ./package.nix {
          src = inputs.openclaw-src;
          pnpmDepsHash = pnpmDepsHash;
        };

      # Default packages (without hash override - uses fakeHash initially)
      packages = forAllSystems (system: mkOpenclawPackage system null);

      # Pass to modules via a flake-like attribute set
      flakeForModules = {
        packages = packages;
        openclawSrc = inputs.openclaw-src;
        mkOpenclawPackage = mkOpenclawPackage;
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { pkgs, ... }:
        let
          openclaw-pkg = pkgs.callPackage ./package.nix {
            src = inputs.openclaw-src;
          };
        in
        {
          packages = {
            openclaw = openclaw-pkg;
            default = openclaw-pkg;
          };
          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nodejs_22
              nil
              nixfmt-rfc-style
              git
            ];
          };
        };

      flake = {
        overlays.default = final: _prev: {
          openclaw = final.callPackage ./package.nix {
            src = inputs.openclaw-src;
          };
        };

        nixosModules = rec {
          openclaw = import ./modules/nixos.nix flakeForModules;
          default = openclaw;
        };

        homeManagerModules = rec {
          openclaw = import ./modules/home-manager.nix flakeForModules;
          default = openclaw;
        };
      };
    };
}
