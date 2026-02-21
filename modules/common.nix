# ═══════════════════════════════════════════════════════════════════════════════
# File: modules/common.nix
# Description: Shared logic for NixOS and Home-Manager modules.
#
# Provides:
#   • modelOpts type (imported from lib/models.nix)
#   • mkModelsJson: creates models.json from models config
#   • mkGitTrackScript: creates git auto-commit script
#   • mkR2BackupScript: creates R2 backup script
#   • mkR2RestoreScript: creates R2 restore script
# ═══════════════════════════════════════════════════════════════════════════════
{ lib, pkgs }:

let
  modelOpts = import ../lib/models.nix { inherit lib; };

  mkModelsJson =
    models: defaultModel:
    pkgs.writeText "openclaw-models.json" (
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
        ) models;
        defaultModel =
          if defaultModel != null then
            defaultModel
          else
            let
              d = lib.filterAttrs (_: m: m.isDefault or false) models;
            in
            if d != { } then
              builtins.head (builtins.attrNames d)
            else if models != { } then
              builtins.head (builtins.attrNames models)
            else
              null;
      }
    );

  mkGitTrackScript =
    {
      dataDir,
      scriptName,
      environmentFiles ? [ ],
    }:
    pkgs.writeShellScript scriptName ''
      set -euo pipefail
      cd "${dataDir}"
      if [ ! -d ".git" ]; then
        ${pkgs.git}/bin/git init
        ${pkgs.git}/bin/git config user.email "openclaw-tracker@localhost"
        ${pkgs.git}/bin/git config user.name  "OpenClaw Auto-Tracker"
        printf '%s\n' logs/ cache/ '*.tmp' node_modules/ .npm/ secrets/ > .gitignore
        ${pkgs.git}/bin/git add -A
        ${pkgs.git}/bin/git commit -m "init: auto-tracked by nix-openclaw" --allow-empty
      fi

      ${lib.optionalString (environmentFiles != [ ]) ''
        # Source optional environment files
        ${lib.concatMapStringsSep "\n" (f: "source ${f} 2>/dev/null || true") environmentFiles}
      ''}

      ${pkgs.git}/bin/git add -A
      if ! ${pkgs.git}/bin/git diff --cached --quiet 2>/dev/null; then
        TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        STAT=$(${pkgs.git}/bin/git diff --cached --shortstat)
        ${pkgs.git}/bin/git commit -m "auto: $TS — $STAT"
      fi
    '';

  mkR2BackupScript =
    {
      dataDir,
      gitTrackScript ? null,
      retentionCount ? null,
      storageProvider ? "r2",
    }:
    let
      s3Provider =
        {
          r2 = "Cloudflare";
          s3 = "AWS";
          minio = "MinIO";
          other = "";
        }
        .${storageProvider} or "";

      s3ProviderFlag = lib.optionalString (s3Provider != "") "--s3-provider ${s3Provider}";

      bucketPath = "s3:$OPENCLAW_S3_BUCKET/backups";
      retentionLogic = lib.optionalString (retentionCount != null) ''
        ${pkgs.rclone}/bin/rclone lsf \
          "${bucketPath}/" \
          --s3-access-key-id     "$OPENCLAW_S3_ACCESS_KEY_ID" \
          --s3-secret-access-key "$OPENCLAW_S3_SECRET_ACCESS_KEY" \
          --s3-endpoint          "$OPENCLAW_S3_ENDPOINT" \
          ${s3ProviderFlag} \
          --s3-no-check-bucket \
        | sort | head -n -${toString retentionCount} \
        | while IFS= read -r old; do
            ${pkgs.rclone}/bin/rclone deletefile \
              "${bucketPath}/$old" \
              --s3-access-key-id     "$OPENCLAW_S3_ACCESS_KEY_ID" \
              --s3-secret-access-key "$OPENCLAW_S3_SECRET_ACCESS_KEY" \
              --s3-endpoint          "$OPENCLAW_S3_ENDPOINT" \
              ${s3ProviderFlag} \
              --s3-no-check-bucket || true
        done
      '';
    in
    pkgs.writeShellScript "openclaw-backup" ''
      set -euo pipefail
      : "''${OPENCLAW_S3_BUCKET:?must be set}"
      NAME="openclaw-$(date -u +%Y%m%d-%H%M%S).tar.zst"
      TMP="/tmp/$NAME"

      ${lib.optionalString (gitTrackScript != null) ''
        # Commit first so the backup includes the latest state
        ${gitTrackScript} || true
      ''}

      ${pkgs.gnutar}/bin/tar \
        --create --zstd \
        --file="$TMP" \
        --directory="${dataDir}" \
        --exclude='logs' --exclude='cache' --exclude='*.tmp' --exclude='secrets' \
        .

      ${pkgs.rclone}/bin/rclone copyto "$TMP" \
        "${bucketPath}/$NAME" \
        --s3-access-key-id     "''${OPENCLAW_S3_ACCESS_KEY_ID:?}" \
        --s3-secret-access-key "''${OPENCLAW_S3_SECRET_ACCESS_KEY:?}" \
        --s3-endpoint          "''${OPENCLAW_S3_ENDPOINT:?}" \
        ${s3ProviderFlag} \
        --s3-no-check-bucket \
        --verbose

      rm -f "$TMP"

      ${retentionLogic}

      echo "✓ backup uploaded: $NAME"
    '';

  mkR2RestoreScript =
    {
      dataDir,
      gitTrackScript ? null,
      storageProvider ? "r2",
    }:
    let
      s3Provider =
        {
          r2 = "Cloudflare";
          s3 = "AWS";
          minio = "MinIO";
          other = "";
        }
        .${storageProvider} or "";

      s3ProviderFlag = lib.optionalString (s3Provider != "") "--s3-provider ${s3Provider}";

      bucketPath = "s3:$OPENCLAW_S3_BUCKET/backups";
    in
    pkgs.writeShellScript "openclaw-restore" ''
      set -euo pipefail
      : "''${OPENCLAW_S3_BUCKET:?must be set}"

      FILE="''${1:-}"
      if [ -z "$FILE" ]; then
        echo "Available backups:"
        ${pkgs.rclone}/bin/rclone lsf \
          "${bucketPath}/" \
          --s3-access-key-id     "''${OPENCLAW_S3_ACCESS_KEY_ID:?}" \
          --s3-secret-access-key "''${OPENCLAW_S3_SECRET_ACCESS_KEY:?}" \
          --s3-endpoint          "''${OPENCLAW_S3_ENDPOINT:?}" \
          ${s3ProviderFlag} \
          --s3-no-check-bucket | sort
        echo ""; echo "Usage: openclaw-restore <filename>"; exit 1
      fi

      TMP="/tmp/openclaw-restore.tar.zst"
      ${pkgs.rclone}/bin/rclone copyto \
        "${bucketPath}/$FILE" "$TMP" \
        --s3-access-key-id     "''${OPENCLAW_S3_ACCESS_KEY_ID:?}" \
        --s3-secret-access-key "''${OPENCLAW_S3_SECRET_ACCESS_KEY:?}" \
        --s3-endpoint          "''${OPENCLAW_S3_ENDPOINT:?}" \
        ${s3ProviderFlag} \
        --s3-no-check-bucket --verbose

      ${lib.optionalString (gitTrackScript != null) ''
        # Safety: snapshot current state before overwriting
        ${gitTrackScript} || true
      ''}

      ${pkgs.gnutar}/bin/tar --extract --zstd --file="$TMP" --directory="${dataDir}"
      rm -f "$TMP"
      echo "✓ restored from $FILE — restart openclaw-gateway.service to apply"
    '';

in
{
  inherit
    modelOpts
    mkModelsJson
    mkGitTrackScript
    mkR2BackupScript
    mkR2RestoreScript
    ;
}
