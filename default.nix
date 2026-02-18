# ═══════════════════════════════════════════════════════════════════════════════
# File: default.nix
# Description: Entry-point for non-flake users.
#
# Usage (in configuration.nix):
#
#   let nix-openclaw = import (fetchTarball "https://github.com/…/nix-openclaw/archive/main.tar.gz");
#   in {
#     imports = [ nix-openclaw.nixosModule ];
#     services.openclaw.enable = true;
#     services.openclaw.package = nix-openclaw.package pkgs;
#   }
# ═══════════════════════════════════════════════════════════════════════════════
{
  # For non-flake use the consumer must supply `src` or override `package`.
  nixosModule = import ./modules/nixos.nix null;
  homeManagerModule = import ./modules/home-manager.nix null;

  package =
    pkgs:
    pkgs.callPackage ./package.nix {
      src = throw ''
        nix-openclaw: you must supply an OpenClaw source tree.
        Either use the flake interface (which pins the source automatically)
        or pass `src` when calling the package:

          nix-openclaw.package pkgs.override { src = ./path/to/openclaw; }
      '';
    };
}
