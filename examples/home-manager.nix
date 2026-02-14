# ═══════════════════════════════════════════════════════════════════════════════
# File: examples/home-manager.nix
# Description: Home-Manager module usage example.
# ═══════════════════════════════════════════════════════════════════════════════
{ ... }:
{
  services.openclaw = {
    enable = true;
    host   = "127.0.0.1";
    port   = 3000;

    environmentFiles = [ "/home/youruser/.config/openclaw/secrets.env" ];

    models.claude = {
      type      = "anthropic";
      modelName = "claude-sonnet-4-20250514";
      isDefault = true;
    };

    gitTracking = {
      enable   = true;
      interval = "*:0/5";
    };
  };
}