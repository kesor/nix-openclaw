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

  # Resolve the default package.  When consumed via the flake we can derive
  # the package automatically; otherwise the user must set `package`.
  defaultPackage =
    if flake != null then flake.packages.${pkgs.stdenv.hostPlatform.system}.openclaw else null;

  # ── Script: git auto-commit ────────────────────────────────────────────────
  gitTrackScript = pkgs.writeShellScript "openclaw-git-track" ''
    set -euo pipefail
    cd "${cfg.dataDir}"

    if [ ! -d ".git" ]; then
      ${pkgs.git}/bin/git init
      ${pkgs.git}/bin/git config user.email "openclaw-tracker@localhost"
      ${pkgs.git}/bin/git config user.name  "OpenClaw Auto-Tracker"
      cat > .gitignore <<'GI'
    logs/
    cache/
    *.tmp
    *.swp
    node_modules/
    .npm/
    secrets/
    GI
      ${pkgs.git}/bin/git add -A
      ${pkgs.git}/bin/git commit -m "init: auto-tracked by nix-openclaw" --allow-empty
    fi

    ${pkgs.git}/bin/git add -A
    if ! ${pkgs.git}/bin/git diff --cached --quiet 2>/dev/null; then
      TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      STAT=$(${pkgs.git}/bin/git diff --cached --shortstat)
      ${pkgs.git}/bin/git commit -m "auto: $TS — $STAT"
    fi
  '';

  # ── Script: R2 backup ─────────────────────────────────────────────────────
  r2BackupScript = pkgs.writeShellScript "openclaw-r2-backup" ''
    set -euo pipefail
    NAME="openclaw-$(date -u +%Y%m%d-%H%M%S).tar.zst"
    TMP="/tmp/$NAME"

    # Commit first so the backup includes the latest state
    ${gitTrackScript} || true

    ${pkgs.gnutar}/bin/tar \
      --create --zstd \
      --file="$TMP" \
      --directory="${cfg.dataDir}" \
      --exclude='logs' --exclude='cache' --exclude='*.tmp' --exclude='secrets' \
      .

    ${pkgs.rclone}/bin/rclone copyto "$TMP" \
      "r2:''${CLOUDFLARE_R2_BUCKET:?must be set}/backups/$NAME" \
      --s3-provider    Cloudflare \
      --s3-access-key-id     "''${CLOUDFLARE_R2_ACCESS_KEY_ID:?}" \
      --s3-secret-access-key "''${CLOUDFLARE_R2_SECRET_ACCESS_KEY:?}" \
      --s3-endpoint          "''${CLOUDFLARE_R2_ENDPOINT:?}" \
      --s3-no-check-bucket \
      --verbose

    rm -f "$TMP"

    ${lib.optionalString (cfg.backup.retentionCount != null) ''
      ${pkgs.rclone}/bin/rclone lsf \
        "r2:$CLOUDFLARE_R2_BUCKET/backups/" \
        --s3-provider Cloudflare \
        --s3-access-key-id     "$CLOUDFLARE_R2_ACCESS_KEY_ID" \
        --s3-secret-access-key "$CLOUDFLARE_R2_SECRET_ACCESS_KEY" \
        --s3-endpoint          "$CLOUDFLARE_R2_ENDPOINT" \
        --s3-no-check-bucket \
      | sort | head -n -${toString cfg.backup.retentionCount} \
      | while IFS= read -r old; do
          ${pkgs.rclone}/bin/rclone deletefile \
            "r2:$CLOUDFLARE_R2_BUCKET/backups/$old" \
            --s3-provider Cloudflare \
            --s3-access-key-id     "$CLOUDFLARE_R2_ACCESS_KEY_ID" \
            --s3-secret-access-key "$CLOUDFLARE_R2_SECRET_ACCESS_KEY" \
            --s3-endpoint          "$CLOUDFLARE_R2_ENDPOINT" \
            --s3-no-check-bucket || true
        done
    ''}

    echo "✓ backup uploaded: $NAME"
  '';

  # ── Script: R2 restore ────────────────────────────────────────────────────
  r2RestoreScript = pkgs.writeShellScript "openclaw-r2-restore" ''
    set -euo pipefail
    FILE="''${1:-}"
    if [ -z "$FILE" ]; then
      echo "Available backups on R2:"
      ${pkgs.rclone}/bin/rclone lsf \
        "r2:''${CLOUDFLARE_R2_BUCKET:?}/backups/" \
        --s3-provider Cloudflare \
        --s3-access-key-id     "''${CLOUDFLARE_R2_ACCESS_KEY_ID:?}" \
        --s3-secret-access-key "''${CLOUDFLARE_R2_SECRET_ACCESS_KEY:?}" \
        --s3-endpoint          "''${CLOUDFLARE_R2_ENDPOINT:?}" \
        --s3-no-check-bucket | sort
      echo ""; echo "Usage: openclaw-restore <filename>"; exit 1
    fi

    TMP="/tmp/openclaw-restore.tar.zst"
    ${pkgs.rclone}/bin/rclone copyto \
      "r2:$CLOUDFLARE_R2_BUCKET/backups/$FILE" "$TMP" \
      --s3-provider Cloudflare \
      --s3-access-key-id     "$CLOUDFLARE_R2_ACCESS_KEY_ID" \
      --s3-secret-access-key "$CLOUDFLARE_R2_SECRET_ACCESS_KEY" \
      --s3-endpoint          "$CLOUDFLARE_R2_ENDPOINT" \
      --s3-no-check-bucket --verbose

    # Safety: snapshot current state before overwriting
    ${gitTrackScript} || true

    ${pkgs.gnutar}/bin/tar --extract --zstd --file="$TMP" --directory="${cfg.dataDir}"
    rm -f "$TMP"
    echo "✓ restored from $FILE — restart openclaw-gateway.service to apply"
  '';

  # ── Generate models.json from Nix attrset ─────────────────────────────────
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
            ;
          inherit (m) isDefault extraConfig;
        }
      ) cfg.models;
      defaultModel =
        if cfg.defaultModel != null then
          cfg.defaultModel
        else
          let
            d = lib.filterAttrs (_: m: m.isDefault) cfg.models;
          in
          if d != { } then
            builtins.head (builtins.attrNames d)
          else if cfg.models != { } then
            builtins.head (builtins.attrNames cfg.models)
          else
            null;
    }
  );

  # ── Model sub-module type ──────────────────────────────────────────────────
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
        description = "Backend type for this model.";
      };
      modelName = lib.mkOption {
        type = lib.types.str;
        description = "Model identifier (e.g. `claude-sonnet-4-20250514`).";
      };
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "API endpoint URL.  Leave empty for provider defaults.";
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
        description = "Arbitrary extra key-values forwarded to the model config.";
      };
    };
  };

in
{
  # ══════════════════════════════════════════════════════════════════════════════
  # OPTIONS
  # ══════════════════════════════════════════════════════════════════════════════
  options.services.openclaw = {
    enable = lib.mkEnableOption "the OpenClaw AI application";

    # ── Package ──────────────────────────────────────────────────────────────
    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "flake.packages.\${system}.openclaw";
      description = ''
        OpenClaw derivation to run.  Override to use a local build or
        different version.
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
      type = lib.types.attrsOf modelOpts;
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

    # ── R2 backup ────────────────────────────────────────────────────────────
    backup = {
      enable = lib.mkEnableOption "Cloudflare R2 backups";
      interval = lib.mkOption {
        type = lib.types.str;
        default = "hourly";
      };
      retentionCount = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = 168;
        description = "Remote backups to keep (null = unlimited).";
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
        ];
        description = "Additional packages available in openclaw user's PATH.";
      };
    };
  };

  # ══════════════════════════════════════════════════════════════════════════════
  # IMPLEMENTATION
  # ══════════════════════════════════════════════════════════════════════════════
  config = lib.mkIf cfg.enable {

    # ── Assertions ───────────────────────────────────────────────────────────
    assertions = [
      {
        assertion = cfg.package != null;
        message = ''
          services.openclaw.package must be set.
          If you are using the flake, this is automatic.
          Otherwise, build or supply the OpenClaw package manually.
        '';
      }
    ];

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
    };
    users.groups.${cfg.group} = { };

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
    systemd.services.openclaw-gateway = {
      description = "OpenClaw AI Gateway";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        NODE_ENV = "production";
        OPENCLAW_STATE_DIR = cfg.dataDir;
        OPENCLAW_NIX_MODE = "1";
        OPENCLAW_GATEWAY_PORT = toString cfg.port;
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
        ExecStart = "${cfg.package}/bin/openclaw-gateway";
        Restart = "always";
        RestartSec = 5;
        WorkingDirectory = cfg.dataDir;

        EnvironmentFile = cfg.environmentFiles;

        # ── Resource limits ──────────────────────────────────────────────
        LimitNOFILE = 65536;
        MemoryMax = "8G";
        CPUQuota = "400%";

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
    systemd.services.openclaw-git-track = lib.mkIf cfg.gitTracking.enable {
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

    systemd.timers.openclaw-git-track = lib.mkIf cfg.gitTracking.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.gitTracking.interval;
        Persistent = true;
        RandomizedDelaySec = 30;
      };
    };

    # ── R2 backup ────────────────────────────────────────────────────────────
    systemd.services.openclaw-backup = lib.mkIf cfg.backup.enable {
      description = "Backup OpenClaw data to Cloudflare R2";
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

    systemd.timers.openclaw-backup = lib.mkIf cfg.backup.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backup.interval;
        Persistent = true;
        RandomizedDelaySec = 300;
      };
    };

    # ── CLI convenience wrappers ─────────────────────────────────────────────
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "openclaw-status" ''
        set -euo pipefail
        echo "══ service ══"
        systemctl status openclaw-gateway.service --no-pager 2>&1 || true
        echo ""
        echo "══ last 25 log lines ══"
        journalctl -u openclaw-gateway.service -n 25 --no-pager 2>&1 || true
        echo ""
        echo "══ disk usage ══"
        du -sh ${cfg.dataDir}/*/ 2>/dev/null || echo "(empty)"
        ${lib.optionalString cfg.gitTracking.enable ''
          echo ""
          echo "══ git log (last 10) ══"
          cd ${cfg.dataDir} && ${pkgs.git}/bin/git log --oneline -10 2>/dev/null || echo "(no commits)"
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
        exec sudo su - ${cfg.user} "$@"
      '')

      pkgs.git
      pkgs.jq
    ]
    ++ lib.optionals cfg.clawhub.enable [
      (pkgs.callPackage ../clawhub.nix { })
    ];
  };
}
