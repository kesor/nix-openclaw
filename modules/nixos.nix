# ═══════════════════════════════════════════════════════════════════════════════
# File: modules/nixos.nix
# Description: Full NixOS module for OpenClaw.
#
# Provides:
#   • Sandboxed systemd service
#   • Declarative multi-model AI backend configuration
#   • Git-based change tracking (auto-commit timer)
#   • Cloudflare R2 encrypted backups with retention
#   • Convenience CLI wrappers
#   • Optional read-only access to NixOS config for self-management proposals
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
      if cfg.packageOverride != null then cfg.packageOverride base else base
    else
      throw "services.openclaw requires flake to be used";

  gitTrackScript = common.mkGitTrackScript {
    dataDir = cfg.dataDir;
    scriptName = "openclaw-git-track";
    environmentFiles = cfg.environmentFiles;
  };

  r2BackupScript = common.mkR2BackupScript {
    dataDir = cfg.dataDir;
    gitTrackScript = gitTrackScript;
    retentionCount = cfg.backup.retentionCount;
    storageProvider = cfg.backup.storageProvider;
  };

  r2RestoreScript = common.mkR2RestoreScript {
    dataDir = cfg.dataDir;
    gitTrackScript = gitTrackScript;
    storageProvider = cfg.backup.storageProvider;
  };

  modelsJson = common.mkModelsJson cfg.models cfg.defaultModel;

in
{
  # ══════════════════════════════════════════════════════════════════════════════
  # OPTIONS
  # ══════════════════════════════════════════════════════════════════════════════
  options.services.openclaw = {
    enable = lib.mkEnableOption "the OpenClaw AI application";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "OpenClaw package to use. When set, pnpmDepsHash and packageOverride are ignored.";
    };

    packageOverride = lib.mkOption {
      type = lib.types.nullOr lib.types.functionTo lib.types.package;
      default = null;
      description = ''
        Function to override the package built from flake.
        Example:
        ```nix
        services.openclaw.packageOverride = pkg: pkg.overrideAttrs (old: {
          patches = [ ./my-fix.patch ];
        });
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

    # ── Identity ─────────────────────────────────────────────────────────────
    user = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "openclaw";
    };

    # ── Paths ────────────────────────────────────────────────────────────────
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openclaw";
      description = "Root directory for all persistent OpenClaw state.";
    };

    # ── Network ──────────────────────────────────────────────────────────────
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
    };

    # ── Secrets ──────────────────────────────────────────────────────────────
    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Paths to systemd `EnvironmentFile=` files containing secrets
        (one `KEY=VALUE` per line).  See the README for required variables.
      '';
    };

    # ── Extra env (non-secret) ───────────────────────────────────────────────
    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Non-secret environment variables passed to OpenClaw.";
    };

    # ── Models ───────────────────────────────────────────────────────────────
    models = lib.mkOption {
      type = lib.types.attrsOf common.modelOpts;
      default = { };
      description = "Declarative AI model backend definitions.";
    };

    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Key into `models` to use as the default.";
    };

    # ── ROCm ─────────────────────────────────────────────────────────────────
    rocm = {
      enable = lib.mkEnableOption "AMD ROCm GPU pass-through";
      gfxVersion = lib.mkOption {
        type = lib.types.str;
        default = "11.0.0";
        description = "HSA_OVERRIDE_GFX_VERSION for your GPU (e.g. 10.3.0, 11.0.0).";
      };
      deviceIds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "0" ];
      };
    };

    # ── Git tracking ─────────────────────────────────────────────────────────
    gitTracking = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      interval = lib.mkOption {
        type = lib.types.str;
        default = "*:0/5";
        description = "systemd OnCalendar expression (default: every 5 min).";
      };
    };

    # ── Backup ────────────────────────────────────────────────────────────────
    backup = {
      enable = lib.mkEnableOption "S3-compatible storage backups (Cloudflare R2, AWS S3, MinIO, etc.)";
      interval = lib.mkOption {
        type = lib.types.str;
        default = "hourly";
      };
      retentionCount = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = 168;
        description = "Remote backups to keep (null = unlimited).";
      };
      storageProvider = lib.mkOption {
        type = lib.types.enum [
          "r2"
          "s3"
          "minio"
          "other"
        ];
        default = "r2";
        description = ''
          S3-compatible storage provider. This configures the --s3-provider flag
          for rclone for optimal compatibility with each backend.
          - r2: Cloudflare R2 (default)
          - s3: AWS S3 or compatible
          - minio: MinIO or compatible
          - other: Generic S3-compatible (specify endpoint URL)
        '';
      };
    };

    # ── Sandbox knobs ────────────────────────────────────────────────────────
    sandbox = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable strict systemd sandboxing.  Disable for debugging.";
      };
      extraReadPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      extraWritePaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

    # ── NixOS self-management ────────────────────────────────────────────────
    nixosConfigDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        If set, OpenClaw gets read-only access to this path and a proposals
        directory is created for it to suggest NixOS changes.
      '';
    };

    # ── ClawHub integration ──────────────────────────────────────────────────
    clawhub = {
      enable = lib.mkEnableOption "ClawHub skill registry integration (via npx)";
    };

    # ── Shell access ─────────────────────────────────────────────────────────
    shell = {
      enable = lib.mkEnableOption "interactive shell access for openclaw user";
      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs; [
          bash
          coreutils
          findutils
          gnugrep
          gnused
          git
          curl
          jq
          nodejs
          python3
        ];
        description = "Additional packages available in openclaw user's PATH.";
      };
    };

    # ── User services ────────────────────────────────────────────────────────
    runAsUserServices = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run OpenClaw services as user services instead of system services.
        Enables lingering for the openclaw user.
      '';
    };

    # ── Headless browser ─────────────────────────────────────────────────────
    browser = {
      enable = lib.mkEnableOption "headless Chrome/Chromium for browser automation";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.chromium;
        description = "Browser package to use (chromium or google-chrome)";
      };
      debugPort = lib.mkOption {
        type = lib.types.port;
        default = 9222;
        description = "Chrome DevTools Protocol port";
      };
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional command-line arguments for Chrome/Chromium";
      };
      useVirtualDisplay = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run Chrome with Xvfb virtual display instead of headless mode";
      };
      vncPort = lib.mkOption {
        type = lib.types.port;
        default = 5900;
        description = "VNC port for accessing Chrome display (when useVirtualDisplay is enabled)";
      };
      vncPassword = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          VNC password for authentication. When null (default), password-less access is used.
          WARNING: Even with -localhost, this allows any local user to access your session.
          Consider using SSH tunneling or restricting to trusted single-user systems.
          When set, password file is created at $dataDir/.vnc/passwd.
        '';
      };
      displayResolution = lib.mkOption {
        type = lib.types.str;
        default = "2560x1440x24";
        description = "Virtual display resolution (when useVirtualDisplay is enabled)";
      };
      displayNumber = lib.mkOption {
        type = lib.types.str;
        default = ":99";
        description = "Xvfb display number for virtual display mode";
      };
    };

    # ── Tuning / Performance ───────────────────────────────────────────────────
    tuning = {
      restart = {
        limitBurst = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "StartLimitBurst - max restarts within interval before stopping";
        };
        limitInterval = lib.mkOption {
          type = lib.types.int;
          default = 300;
          description = "StartLimitIntervalSec - time window for restart limits (seconds)";
        };
        sec = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = "RestartSec - seconds to wait before restarting";
        };
      };
      resources = {
        maxMemory = lib.mkOption {
          type = lib.types.str;
          default = "8G";
          description = "MemoryMax - maximum memory the service can use";
        };
        maxFiles = lib.mkOption {
          type = lib.types.int;
          default = 65536;
          description = "LimitNOFILE - maximum number of open files";
        };
        cpuQuota = lib.mkOption {
          type = lib.types.str;
          default = "400%";
          description = "CPUQuota - maximum CPU time (100% = 1 core, 200% = 2 cores, etc.)";
        };
      };
      gitTracking = {
        randomDelay = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "RandomizedDelaySec - random delay before git auto-commit (seconds)";
        };
      };
      backup = {
        randomDelay = lib.mkOption {
          type = lib.types.int;
          default = 300;
          description = "RandomizedDelaySec - random delay before backup (seconds)";
        };
      };
      status = {
        logLines = lib.mkOption {
          type = lib.types.int;
          default = 25;
          description = "Number of log lines to show in openclaw-status";
        };
        gitLogLines = lib.mkOption {
          type = lib.types.int;
          default = 10;
          description = "Number of git commits to show in openclaw-status";
        };
      };
    };
  };

  # ══════════════════════════════════════════════════════════════════════════════
  # IMPLEMENTATION
  # ══════════════════════════════════════════════════════════════════════════════
  config = lib.mkIf cfg.enable {

    # ── Assertions ───────────────────────────────────────────────────────────

    # ── User / Group ─────────────────────────────────────────────────────────
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      description = "OpenClaw service account";
      shell = if cfg.shell.enable then pkgs.bash else pkgs.shadow;
      extraGroups = lib.optionals cfg.rocm.enable [
        "video"
        "render"
      ];
      packages = lib.optionals cfg.shell.enable (cfg.shell.extraPackages ++ [ openclawPackage ]);
    };
    users.groups.${cfg.group} = { };

    # Create VNC password file if configured
    system.activationScripts.openclaw-vnc-password = lib.mkIf (cfg.browser.vncPassword != null) ''
      mkdir -p ${cfg.dataDir}/.vnc
      printf '%s\n%s\n' "${cfg.browser.vncPassword}" "${cfg.browser.vncPassword}" | ${pkgs.x11vnc}/bin/x11vnc -storepasswd -f > ${cfg.dataDir}/.vnc/passwd 2>/dev/null || true
      chmod 600 ${cfg.dataDir}/.vnc/passwd
      chown ${cfg.user}:${cfg.group} ${cfg.dataDir}/.vnc/passwd
    '';

    # Source environment files in openclaw user's bash profile
    system.activationScripts.openclaw-bashrc = lib.mkIf cfg.shell.enable ''
      cat > ${cfg.dataDir}/.bashrc << 'EOF'
      ${lib.concatMapStringsSep "\n" (
        f: "[ -f ${f} ] && set -a && source ${f} && set +a"
      ) cfg.environmentFiles}
      [ -f "${cfg.dataDir}/.openclaw/completions/openclaw.bash" ] && source "${cfg.dataDir}/.openclaw/completions/openclaw.bash"
      EOF
      cat > ${cfg.dataDir}/.bash_profile << 'EOF'
      [ -f ~/.bashrc ] && source ~/.bashrc
      EOF
      chown ${cfg.user}:${cfg.group} ${cfg.dataDir}/.bashrc ${cfg.dataDir}/.bash_profile
    '';

    # ── Directories ──────────────────────────────────────────────────────────
    systemd.tmpfiles.rules =
      let
        o = "${cfg.user}";
        g = "${cfg.group}";
      in
      [
        "d ${cfg.dataDir}            0750 ${o} ${g} -"
        "d ${cfg.dataDir}/data       0750 ${o} ${g} -"
        "d ${cfg.dataDir}/config     0750 ${o} ${g} -"
        "d ${cfg.dataDir}/logs       0750 ${o} ${g} -"
        "d ${cfg.dataDir}/cache      0750 ${o} ${g} -"
        "d ${cfg.dataDir}/staging    0750 ${o} ${g} -"
        "d ${cfg.dataDir}/secrets    0700 ${o} ${g} -"
      ]
      ++ lib.optionals (cfg.browser.vncPassword != null) [ "d ${cfg.dataDir}/.vnc      0700 ${o} ${g} -" ]
      ++ lib.optionals (cfg.nixosConfigDir != null) [
        "d ${cfg.dataDir}/nixos-proposals 0750 ${o} ${g} -"
      ]
      ++ lib.optionals cfg.clawhub.enable [
        "d ${cfg.dataDir}/cache/clawhub 0750 ${o} ${g} -"
        "d ${cfg.dataDir}/skills 0750 ${o} ${g} -"
      ];

    # ── ROCm hardware ────────────────────────────────────────────────────────
    hardware.graphics = lib.mkIf cfg.rocm.enable {
      enable = true;
      extraPackages = with pkgs; [
        rocmPackages.clr
        rocmPackages.clr.icd
      ];
    };

    # ── Main service ─────────────────────────────────────────────────────────
    systemd.services.openclaw-gateway = lib.mkIf (!cfg.runAsUserServices) {
      description = "OpenClaw AI Gateway";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # Restart limits go in [Unit] section
      unitConfig = {
        StartLimitBurst = cfg.tuning.restart.limitBurst;
        StartLimitIntervalSec = cfg.tuning.restart.limitInterval;
      };

      environment = {
        NODE_ENV = "production";
        OPENCLAW_STATE_DIR = cfg.dataDir;
        OPENCLAW_NIX_MODE = "1";
        OPENCLAW_GATEWAY_PORT = toString cfg.port;
        OPENCLAW_MODELS_CONFIG = toString modelsJson;
        HOME = cfg.dataDir;
      }
      // lib.optionalAttrs cfg.rocm.enable {
        HSA_OVERRIDE_GFX_VERSION = cfg.rocm.gfxVersion;
        HIP_VISIBLE_DEVICES = lib.concatStringsSep "," cfg.rocm.deviceIds;
      }
      // lib.optionalAttrs (cfg.nixosConfigDir != null) {
        OPENCLAW_NIXOS_CONFIG_DIR = cfg.nixosConfigDir;
        OPENCLAW_NIXOS_PROPOSALS_DIR = "${cfg.dataDir}/nixos-proposals";
      }
      // lib.optionalAttrs cfg.clawhub.enable { CLAWHUB_CACHE_DIR = "${cfg.dataDir}/cache/clawhub"; }
      // cfg.extraEnvironment;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${openclawPackage}/bin/openclaw-gateway";
        Restart = "always";
        RestartSec = cfg.tuning.restart.sec;
        WorkingDirectory = cfg.dataDir;

        EnvironmentFile = cfg.environmentFiles;

        # ── Resource limits ──────────────────────────────────────────────
        LimitNOFILE = cfg.tuning.resources.maxFiles;
        MemoryMax = cfg.tuning.resources.maxMemory;
        CPUQuota = cfg.tuning.resources.cpuQuota;

        # ── Logging ──────────────────────────────────────────────────────
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "openclaw";
      }
      # ── Security hardening (conditional) ─────────────────────────────────
      // lib.optionalAttrs cfg.sandbox.enable {
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        NoNewPrivileges = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        MemoryDenyWriteExecute = false; # Node.js V8 JIT requires W|X

        CapabilityBoundingSet = "";
        AmbientCapabilities = "";

        PrivateUsers = !cfg.rocm.enable;
        PrivateDevices = !cfg.rocm.enable;

        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
          "AF_NETLINK"
        ];
        SystemCallFilter = [
          "@system-service"
          "~@mount"
          "~@reboot"
          "~@swap"
        ];
        SystemCallArchitectures = "native";

        ReadWritePaths = [ cfg.dataDir ] ++ cfg.sandbox.extraWritePaths;

        ReadOnlyPaths =
          lib.optionals (cfg.nixosConfigDir != null) [ cfg.nixosConfigDir ] ++ cfg.sandbox.extraReadPaths;
      }
      // lib.optionalAttrs (cfg.sandbox.enable && cfg.rocm.enable) {
        DevicePolicy = "auto";
        DeviceAllow = [
          "/dev/kfd rw"
          "/dev/dri/card0 rw"
          "/dev/dri/renderD128 rw"
        ];
      };
    };

    # ── Git auto-tracking ────────────────────────────────────────────────────
    systemd.services.openclaw-git-track = lib.mkIf (!cfg.runAsUserServices && cfg.gitTracking.enable) {
      description = "Auto-commit OpenClaw data changes";
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = gitTrackScript;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ReadWritePaths = [ cfg.dataDir ];
        NoNewPrivileges = true;
      };
      path = [
        pkgs.git
        pkgs.nodejs
        pkgs.nodePackages.npm
      ];
    };

    systemd.timers.openclaw-git-track = lib.mkIf (!cfg.runAsUserServices && cfg.gitTracking.enable) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.gitTracking.interval;
        Persistent = true;
        RandomizedDelaySec = cfg.tuning.gitTracking.randomDelay;
      };
    };

    # ── R2 backup ────────────────────────────────────────────────────────────
    systemd.services.openclaw-backup = lib.mkIf (!cfg.runAsUserServices && cfg.backup.enable) {
      description = "Backup OpenClaw data to S3-compatible storage";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = r2BackupScript;
        EnvironmentFile = cfg.environmentFiles;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ReadOnlyPaths = [ cfg.dataDir ];
        ReadWritePaths = [ "/tmp" ];
        NoNewPrivileges = true;
      };
      path = [
        pkgs.rclone
        pkgs.gnutar
        pkgs.zstd
        pkgs.git
      ];
    };

    systemd.timers.openclaw-backup = lib.mkIf (!cfg.runAsUserServices && cfg.backup.enable) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backup.interval;
        Persistent = true;
        RandomizedDelaySec = cfg.tuning.backup.randomDelay;
      };
    };

    # ── CLI convenience wrappers ─────────────────────────────────────────────
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "openclaw" ''
        set -a
        ${lib.concatMapStringsSep "\n" (f: "source ${f} 2>/dev/null || true") cfg.environmentFiles}
        set +a
        exec sudo -u ${cfg.user} ${openclawPackage}/bin/openclaw "$@"
      '')

      (pkgs.writeShellScriptBin "openclaw-status" ''
        set -euo pipefail
        echo "══ service ══"
        systemctl status openclaw-gateway.service --no-pager 2>&1 || true
        echo ""
        echo "══ last ${toString cfg.tuning.status.logLines} log lines ══"
        journalctl -u openclaw-gateway.service -n ${toString cfg.tuning.status.logLines} --no-pager 2>&1 || true
        echo ""
        echo "══ disk usage ══"
        du -sh ${cfg.dataDir}/*/ 2>/dev/null || echo "(empty)"
        ${lib.optionalString cfg.gitTracking.enable ''
          echo ""
          echo "══ git log (last ${toString cfg.tuning.status.gitLogLines}) ══"
          cd ${cfg.dataDir} && ${pkgs.git}/bin/git log --oneline -${toString cfg.tuning.status.gitLogLines} 2>/dev/null || echo "(no commits)"
        ''}
      '')

      (pkgs.writeShellScriptBin "openclaw-logs" ''
        exec journalctl -u openclaw-gateway.service -f "$@"
      '')

      (pkgs.writeShellScriptBin "openclaw-git" ''
        exec sudo -u ${cfg.user} sh -c "cd ${cfg.dataDir} && ${pkgs.git}/bin/git \"\$@\"" -- "$@"
      '')

      (pkgs.writeShellScriptBin "openclaw-backup-now" ''
        echo "Triggering backup…"
        sudo systemctl start openclaw-backup.service
        journalctl -u openclaw-backup.service --since "30 seconds ago" --no-pager
      '')

      (pkgs.writeShellScriptBin "openclaw-restore" ''
        set -a
        ${lib.concatMapStringsSep "\n" (f: "source ${f}") cfg.environmentFiles}
        set +a
        exec ${r2RestoreScript} "$@"
      '')

      (pkgs.writeShellScriptBin "openclaw-shell" ''
        exec sudo machinectl shell ${cfg.user}@
      '')

      pkgs.git
      pkgs.jq
    ]
    ++ lib.optionals cfg.clawhub.enable [ (pkgs.callPackage ../clawhub.nix { }) ];

    # ── User services conversion ─────────────────────────────────────────────
    systemd.user.services.openclaw-gateway = lib.mkIf cfg.runAsUserServices {
      description = "OpenClaw AI Gateway";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "default.target" ];

      # Restart limits go in [Unit] section
      unitConfig = {
        StartLimitBurst = cfg.tuning.restart.limitBurst;
        StartLimitIntervalSec = cfg.tuning.restart.limitInterval;
      };

      environment = {
        NODE_ENV = "production";
        OPENCLAW_STATE_DIR = cfg.dataDir;
        OPENCLAW_NIX_MODE = "1";
        OPENCLAW_GATEWAY_PORT = toString cfg.port;
        OPENCLAW_MODELS_CONFIG = toString modelsJson;
        HOME = cfg.dataDir;
      }
      // lib.optionalAttrs cfg.rocm.enable {
        HSA_OVERRIDE_GFX_VERSION = cfg.rocm.gfxVersion;
        HIP_VISIBLE_DEVICES = lib.concatStringsSep "," cfg.rocm.deviceIds;
      }
      // lib.optionalAttrs (cfg.nixosConfigDir != null) {
        OPENCLAW_NIXOS_CONFIG_DIR = cfg.nixosConfigDir;
        OPENCLAW_NIXOS_PROPOSALS_DIR = "${cfg.dataDir}/nixos-proposals";
      }
      // lib.optionalAttrs cfg.clawhub.enable { CLAWHUB_CACHE_DIR = "${cfg.dataDir}/cache/clawhub"; }
      // cfg.extraEnvironment;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${openclawPackage}/bin/openclaw-gateway";
        Restart = "always";
        RestartSec = cfg.tuning.restart.sec;
        WorkingDirectory = cfg.dataDir;
        EnvironmentFile = cfg.environmentFiles;
        LimitNOFILE = cfg.tuning.resources.maxFiles;
        MemoryMax = cfg.tuning.resources.maxMemory;
        CPUQuota = cfg.tuning.resources.cpuQuota;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "openclaw";
      };
    };

    systemd.user.services.openclaw-git-track =
      lib.mkIf (cfg.runAsUserServices && cfg.gitTracking.enable)
        {
          description = "Auto-commit OpenClaw data changes";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = gitTrackScript;
          };
          path = [
            pkgs.git
            pkgs.nodejs
            pkgs.nodePackages.npm
          ];
        };

    systemd.user.services.openclaw-backup = lib.mkIf (cfg.runAsUserServices && cfg.backup.enable) {
      description = "Backup OpenClaw data to S3-compatible storage";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = r2BackupScript;
        EnvironmentFile = cfg.environmentFiles;
      };
      path = [
        pkgs.rclone
        pkgs.gnutar
        pkgs.zstd
        pkgs.git
      ];
    };

    systemd.user.services.openclaw-xvfb =
      lib.mkIf (cfg.runAsUserServices && cfg.browser.enable && cfg.browser.useVirtualDisplay)
        {
          description = "Xvfb virtual display for OpenClaw Chrome";
          before = [ "openclaw-chrome.service" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.xorg.xorgserver}/bin/Xvfb ${cfg.browser.displayNumber} -screen 0 ${cfg.browser.displayResolution} -nolisten tcp -br";
            Restart = "always";
            RestartSec = "${toString cfg.tuning.restart.sec}s";
          };
          environment = {
            HOME = cfg.dataDir;
          };
        };

    systemd.user.services.openclaw-openbox =
      lib.mkIf (cfg.runAsUserServices && cfg.browser.enable && cfg.browser.useVirtualDisplay)
        {
          description = "Openbox window manager for OpenClaw Chrome";
          after = [ "openclaw-xvfb.service" ];
          requires = [ "openclaw-xvfb.service" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.openbox}/bin/openbox";
            Restart = "always";
            RestartSec = "${toString cfg.tuning.restart.sec}s";
          };
          environment = {
            HOME = cfg.dataDir;
            DISPLAY = cfg.browser.displayNumber;
          };
        };

    systemd.user.services.openclaw-tint2 =
      lib.mkIf (cfg.runAsUserServices && cfg.browser.enable && cfg.browser.useVirtualDisplay)
        {
          description = "Tint2 panel for OpenClaw Chrome";
          after = [ "openclaw-openbox.service" ];
          requires = [ "openclaw-openbox.service" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.tint2}/bin/tint2";
            Restart = "always";
            RestartSec = "${toString cfg.tuning.restart.sec}s";
          };
          environment = {
            HOME = cfg.dataDir;
            DISPLAY = cfg.browser.displayNumber;
          };
        };

    systemd.user.services.openclaw-vnc =
      lib.mkIf (cfg.runAsUserServices && cfg.browser.enable && cfg.browser.useVirtualDisplay)
        {
          description = "VNC server for OpenClaw Chrome display";
          after = [ "openclaw-xvfb.service" ];
          requires = [ "openclaw-xvfb.service" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart =
              let
                vncAuth =
                  if cfg.browser.vncPassword != null then "-rfbauth ${cfg.dataDir}/.vnc/passwd" else "-nopw";
              in
              "${pkgs.x11vnc}/bin/x11vnc -display ${cfg.browser.displayNumber} ${vncAuth} -forever -rfbport ${toString cfg.browser.vncPort} -shared -localhost";
            Restart = "always";
            RestartSec = "${toString cfg.tuning.restart.sec}s";
          };
          environment = {
            HOME = cfg.dataDir;
          };
        };

    systemd.user.services.openclaw-chrome = lib.mkIf (cfg.runAsUserServices && cfg.browser.enable) {
      description = "Headless Chrome for OpenClaw browser automation";
      after = [
        "network-online.target"
      ]
      ++ lib.optional cfg.browser.useVirtualDisplay "openclaw-xvfb.service";
      wants = [ "network-online.target" ];
      requires = lib.optional cfg.browser.useVirtualDisplay "openclaw-xvfb.service";
      wantedBy = [ "default.target" ];
      preStart = ''
        mkdir -p ${cfg.dataDir}/.chrome-extension
        cp -r ${openclawPackage}/lib/openclaw/assets/chrome-extension/* ${cfg.dataDir}/.chrome-extension/
        chown -R ${cfg.user}:${cfg.group} ${cfg.dataDir}/.chrome-extension
      '';
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.browser.package}/bin/${cfg.browser.package.meta.mainProgram or "chromium"} ${
          lib.optionalString (!cfg.browser.useVirtualDisplay) "--headless"
        } --remote-debugging-port=${toString cfg.browser.debugPort} --remote-debugging-address=127.0.0.1 --no-sandbox --disable-gpu --disable-dev-shm-usage --disable-software-rasterizer --user-data-dir=${cfg.dataDir}/.chrome-profile --load-extension=${cfg.dataDir}/.chrome-extension ${lib.escapeShellArgs cfg.browser.extraArgs}";
        Restart = "always";
        RestartSec = "5s";
      };
      environment = lib.optionalAttrs cfg.browser.useVirtualDisplay {
        DISPLAY = cfg.browser.displayNumber;
      };
    };

    systemd.user.timers.openclaw-git-track =
      lib.mkIf (cfg.runAsUserServices && cfg.gitTracking.enable)
        {
          description = "Auto-commit OpenClaw data changes";
          timerConfig = {
            OnCalendar = cfg.gitTracking.interval;
            Persistent = true;
            RandomizedDelaySec = cfg.tuning.gitTracking.randomDelay;
          };
          wantedBy = [ "timers.target" ];
        };

    systemd.user.timers.openclaw-backup = lib.mkIf (cfg.runAsUserServices && cfg.backup.enable) {
      description = "Backup OpenClaw data to S3-compatible storage";
      timerConfig = {
        OnCalendar = cfg.backup.interval;
        Persistent = true;
        RandomizedDelaySec = cfg.tuning.backup.randomDelay;
      };
      wantedBy = [ "timers.target" ];
    };

    # Enable lingering for openclaw user when using user services
    system.activationScripts.openclaw-linger = lib.mkIf cfg.runAsUserServices (
      lib.stringAfter [ "users" ] ''
        ${pkgs.systemd}/bin/loginctl enable-linger ${cfg.user} || true
      ''
    );
  };
}
