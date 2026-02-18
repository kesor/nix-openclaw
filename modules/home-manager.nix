# ═══════════════════════════════════════════════════════════════════════════════
# File: modules/home-manager.nix
# Description: Home-Manager module for OpenClaw (user-level service).
#
# Use this when:
#   • You don't have root / NixOS system access
#   • You want a per-user development instance
#   • You're on a non-NixOS Linux with Home-Manager standalone
#
# Limitations vs. the NixOS module:
#   • No system user creation (runs as your user)
#   • Reduced systemd sandboxing surface
#   • No hardware.graphics / ROCm kernel configuration
#     (you must configure GPU access at the system level separately)
# ═══════════════════════════════════════════════════════════════════════════════
flake:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.openclaw;

  defaultPackage =
    if flake != null then flake.packages.${pkgs.stdenv.hostPlatform.system}.openclaw else null;

  # Model sub-module (same definition as the NixOS module)
  modelOpts = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [
          "anthropic"
          "openai-compatible"
          "ollama"
          "rocm"
          "remote"
        ];
      };
      modelName = lib.mkOption { type = lib.types.str; };
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      maxTokens = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
      temperature = lib.mkOption {
        type = lib.types.nullOr lib.types.float;
        default = null;
      };
      isDefault = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      extraConfig = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
        default = null;
      };
    };
  };

  modelsJson = pkgs.writeText "openclaw-models.json" (
    builtins.toJSON {
      models = lib.mapAttrs (
        _: m:
        lib.filterAttrs (_: v: v != null) {
          inherit (m)
            type
            modelName
            endpoint
            maxTokens
            temperature
            isDefault
            extraConfig
            ;
        }
      ) cfg.models;
      defaultModel =
        if cfg.defaultModel != null then
          cfg.defaultModel
        else
          let
            d = lib.filterAttrs (_: m: m.isDefault) cfg.models;
          in
          if d != { } then builtins.head (builtins.attrNames d) else null;
    }
  );

  dataDir = cfg.dataDir;

  gitTrackScript = pkgs.writeShellScript "openclaw-hm-git-track" ''
    set -euo pipefail
    cd "${dataDir}"
    if [ ! -d ".git" ]; then
      ${pkgs.git}/bin/git init
      ${pkgs.git}/bin/git config user.email "openclaw-tracker@localhost"
      ${pkgs.git}/bin/git config user.name  "OpenClaw Auto-Tracker"
      printf '%s\n' logs/ cache/ '*.tmp' node_modules/ .npm/ secrets/ > .gitignore
      ${pkgs.git}/bin/git add -A
      ${pkgs.git}/bin/git commit -m "init" --allow-empty
    fi
    ${pkgs.git}/bin/git add -A
    if ! ${pkgs.git}/bin/git diff --cached --quiet 2>/dev/null; then
      TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      ${pkgs.git}/bin/git commit -m "auto: $TS"
    fi
  '';

in
{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw (Home-Manager user service)";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "flake.packages.\${system}.openclaw";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/openclaw";
      description = "Persistent data directory.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };

    models = lib.mkOption {
      type = lib.types.attrsOf modelOpts;
      default = { };
    };
    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    gitTracking = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      interval = lib.mkOption {
        type = lib.types.str;
        default = "*:0/5";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.package != null;
        message = "services.openclaw.package must be set (see README).";
      }
    ];

    # Ensure data directories exist via activation
    home.activation.openclawDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${dataDir}"/{data,config,logs,cache,staging,secrets}
      chmod 700 "${dataDir}/secrets"
    '';

    # ── User service ─────────────────────────────────────────────────────────
    systemd.user.services.openclaw = {
      Unit = {
        Description = "OpenClaw AI Application (user)";
        After = [ "network-online.target" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/openclaw";
        Restart = "always";
        RestartSec = 5;
        WorkingDirectory = dataDir;
        EnvironmentFile = cfg.environmentFiles;
        Environment = lib.mapAttrsToList (k: v: "${k}=${v}") (
          {
            NODE_ENV = "production";
            OPENCLAW_HOST = cfg.host;
            OPENCLAW_PORT = toString cfg.port;
            OPENCLAW_DATA_DIR = "${dataDir}/data";
            OPENCLAW_CONFIG_DIR = "${dataDir}/config";
            OPENCLAW_LOG_DIR = "${dataDir}/logs";
            OPENCLAW_CACHE_DIR = "${dataDir}/cache";
            OPENCLAW_STAGING_DIR = "${dataDir}/staging";
            OPENCLAW_MODELS_CONFIG = toString modelsJson;
            HOME = dataDir;
          }
          // cfg.extraEnvironment
        );
      };
    };

    # ── Git tracking (user timer) ────────────────────────────────────────────
    systemd.user.services.openclaw-git-track = lib.mkIf cfg.gitTracking.enable {
      Unit.Description = "Auto-commit OpenClaw data";
      Service = {
        Type = "oneshot";
        ExecStart = toString gitTrackScript;
      };
    };
    systemd.user.timers.openclaw-git-track = lib.mkIf cfg.gitTracking.enable {
      Unit.Description = "Timer for OpenClaw git auto-tracking";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnCalendar = cfg.gitTracking.interval;
        Persistent = true;
      };
    };

    home.packages = [
      (pkgs.writeShellScriptBin "openclaw-status" ''
        systemctl --user status openclaw.service --no-pager 2>&1 || true
        echo ""; journalctl --user -u openclaw.service -n 15 --no-pager 2>&1 || true
      '')
      (pkgs.writeShellScriptBin "openclaw-logs" ''
        exec journalctl --user -u openclaw.service -f "$@"
      '')
      (pkgs.writeShellScriptBin "openclaw-git" ''
        cd "${dataDir}" && exec ${pkgs.git}/bin/git "$@"
      '')
      pkgs.git
      pkgs.jq
    ];
  };
}
