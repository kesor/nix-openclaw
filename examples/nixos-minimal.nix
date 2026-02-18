# ═══════════════════════════════════════════════════════════════════════════════
# File: examples/nixos-minimal.nix
# Description: Bare-minimum NixOS config snippet to get OpenClaw running.
# ═══════════════════════════════════════════════════════════════════════════════
{ ... }:
{
  services.openclaw = {
    enable = true;
    # All defaults: localhost:3000, git tracking on, no R2 backup.

    environmentFiles = [ "/var/lib/openclaw/secrets/env" ];

    models.claude = {
      type = "anthropic";
      modelName = "claude-sonnet-4-20250514";
      isDefault = true;
    };
  };
}
