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
flake: # null when imported without flakes
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.openclaw;

  common = import ./common.nix { inherit lib pkgs; };

  openclawPackage =
    if cfg.package != null then
      cfg.package
    else if flake != null then
      let
        base = flake.mkOpenclawPackage pkgs.stdenv.hostPlatform.system cfg.pnpmDepsHash;
      in
      if cfg.packageOverride != null then base.override cfg.packageOverride else base
    else
      throw "services.openclaw requires flake to be used";

  dataDir = cfg.dataDir;

  modelsJson = common.mkModelsJson cfg.models cfg.defaultModel;

  gitTrackScript = common.mkGitTrackScript {
    inherit dataDir;
    scriptName = "openclaw-hm-git-track";
  };

in
{
  options.services.openclaw = {
    enable = lib.mkEnableOption "OpenClaw (Home-Manager user service)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "OpenClaw package to use. When set, pnpmDepsHash and packageOverride are ignored.";
    };

    packageOverride = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = ''
        Attrs to override package function parameters.
        Example:
        ```nix
        services.openclaw.packageOverride = {
          nodejs = pkgs.nodejs_20;
        };
        ```
      '';
    };

    pnpmDepsHash = lib.mkOption {
      type = lib.types.str;
      default = lib.fakeHash;
      description = ''
        SHA256 hash of pnpm dependencies. Run `nix build .#openclaw`
        to get the expected hash error with the correct value.
      '';
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
      type = lib.types.attrsOf common.modelOpts;
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

    # ── Tuning / Performance ───────────────────────────────────────────────────
    tuning = {
      restart = {
        sec = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "RestartSec - seconds to wait before restarting";
        };
      };
      gitTracking = {
        randomDelay = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "RandomizedDelaySec - random delay before git auto-commit (seconds)";
        };
      };
      status = {
        logLines = lib.mkOption {
          type = lib.types.int;
          default = 15;
          description = "Number of log lines to show in openclaw-status";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = openclawPackage != null;
        message = "services.openclaw.package must be set (see README).";
      }
    ];

    home.activation.openclawDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${dataDir}"/{data,config,logs,cache,staging,secrets}
      chmod 700 "${dataDir}/secrets"
    '';

    systemd.user.services.openclaw = {
      Unit = {
        Description = "OpenClaw AI Application (user)";
        After = [ "network-online.target" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "simple";
        ExecStart = "${openclawPackage}/bin/openclaw";
        Restart = "always";
        RestartSec = cfg.tuning.restart.sec;
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
        RandomizedDelaySec = cfg.tuning.gitTracking.randomDelay;
      };
    };

    home.packages = [
      (pkgs.writeShellScriptBin "openclaw-status" ''
        systemctl --user status openclaw.service --no-pager 2>&1 || true
        echo ""; journalctl --user -u openclaw.service -n ${toString cfg.tuning.status.logLines} --no-pager 2>&1 || true
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
