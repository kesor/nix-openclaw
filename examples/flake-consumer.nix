# ═══════════════════════════════════════════════════════════════════════════════
# File: examples/flake-consumer.nix
# Description: Example flake.nix for a system that *uses* nix-openclaw.
#              Copy this to your own system config repo and customise.
# ═══════════════════════════════════════════════════════════════════════════════
{
  description = "My NixOS server with OpenClaw";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nix-openclaw - pass openclaw-src as an input to override the default
    nix-openclaw = {
      url = "github:YOUR_USER/nix-openclaw"; # ← your fork / the published repo
      inputs.openclaw-src.url = "github:openclaw/openclaw"; # default
      # Use your own fork:
      # inputs.openclaw-src.url = "github:you/openclaw";
      # Use a private repo (via SSH):
      # inputs.openclaw-src.url = "git+ssh://git@github.com/you/private-openclaw";
      # Use a local path:
      # inputs.openclaw-src.url = "path:/home/you/projects/openclaw";
    };

    # Optional: home-manager for user-level config
    # home-manager.url = "github:nix-community/home-manager";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-openclaw,
      ...
    }:
    {
      nixosConfigurations.my-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hardware-configuration.nix

          # Import the OpenClaw NixOS module
          nix-openclaw.nixosModules.default

          # Your configuration
          (
            { ... }:
            {
              services.openclaw = {
                enable = true;
                port = 3000;
                host = "127.0.0.1";

                environmentFiles = [ "/var/lib/openclaw/secrets/env" ];

                models.claude-sonnet = {
                  type = "anthropic";
                  modelName = "claude-sonnet-4-20250514";
                  isDefault = true;
                };

                gitTracking.enable = true;
                backup.enable = true;
              };
            }
          )

          # … your other modules (cloudflared, etc.)
        ];
      };
    };
}
