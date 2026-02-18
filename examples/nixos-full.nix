# ═══════════════════════════════════════════════════════════════════════════════
# File: examples/nixos-full.nix
# Description: Full-featured NixOS configuration with all bells and whistles.
# ═══════════════════════════════════════════════════════════════════════════════
{ ... }:
{
  services.openclaw = {
    enable = true;
    host = "127.0.0.1"; # cloudflared handles external traffic
    port = 3000;

    # ── Secrets ────────────────────────────────────────────────────────────
    environmentFiles = [ "/var/lib/openclaw/secrets/env" ];

    extraEnvironment = {
      LOG_LEVEL = "info";
    };

    # ── Models ─────────────────────────────────────────────────────────────
    models = {
      claude-sonnet = {
        type = "anthropic";
        modelName = "claude-sonnet-4-20250514";
        maxTokens = 8192;
        isDefault = true;
      };

      claude-haiku = {
        type = "anthropic";
        modelName = "claude-haiku-4-20250514";
        maxTokens = 4096;
      };

      # Local model via ROCm + Ollama
      local-llama = {
        type = "ollama";
        modelName = "llama3.1:70b";
        endpoint = "http://127.0.0.1:11434";
        maxTokens = 4096;
        temperature = 0.7;
      };

      # Remote model on MacBook Pro
      macbook = {
        type = "remote";
        modelName = "llama3.1:8b";
        endpoint = "http://192.168.1.100:11434";
        maxTokens = 4096;
      };

      # Generic OpenAI-compatible server
      my-server = {
        type = "openai-compatible";
        modelName = "mistral-7b";
        endpoint = "http://10.0.0.50:8080/v1";
      };
    };

    defaultModel = "claude-sonnet";

    # ── GPU ────────────────────────────────────────────────────────────────
    rocm = {
      enable = true;
      gfxVersion = "11.0.0"; # Adjust for your AMD GPU
      deviceIds = [ "0" ];
    };

    # ── History ────────────────────────────────────────────────────────────
    gitTracking = {
      enable = true;
      interval = "*:0/2"; # Every 2 min during rapid development
    };

    # ── Backups ────────────────────────────────────────────────────────────
    backup = {
      enable = true;
      interval = "hourly";
      retentionCount = 168; # 7 days × 24 h
    };

    # ── Sandboxing ─────────────────────────────────────────────────────────
    sandbox = {
      enable = true;
      # extraReadPaths  = [ "/some/path" ];
      # extraWritePaths = [ "/some/path" ];
    };

    # ── Allow OpenClaw to read NixOS config & propose changes ──────────────
    nixosConfigDir = "/etc/nixos";
  };

  # Pair with Ollama for local inference
  # services.ollama = {
  #   enable       = true;
  #   acceleration = "rocm";
  #   rocmOverrideGfx = "11.0.0";
  # };
}
