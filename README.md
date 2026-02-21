<!-- ═══════════════════════════════════════════════════════════════════════════
     File: README.md
     ═══════════════════════════════════════════════════════════════════════════ -->

# nix-openclaw

A **NixOS** and **Home-Manager** module for deploying [OpenClaw](https://github.com/openclaw/openclaw) securely.

## What it does

- Runs OpenClaw as a sandboxed systemd service
- Configures AI model backends declaratively (Anthropic, Ollama, ROCm, OpenAI-compatible, remote)
- Auto-commits all changes to git for full history/diff
- Pushes compressed backups to Cloudflare R2 with retention
- Optionally provides AMD GPU access via ROCm

## Quick Start

### 1. Add the flake input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-openclaw.url = "github:your-org/nix-openclaw";
  };

  outputs = { self, nixpkgs, nix-openclaw, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
        nix-openclaw.nixosModules.default
      ];
    };
  };
}
```

### 2. Configure

```nix
# configuration.nix
{ ... }:
{
  services.openclaw = {
    enable = true;
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
```

### 3. Create secrets file

```bash
sudo mkdir -p /var/lib/openclaw/secrets
sudo tee /var/lib/openclaw/secrets/env > /dev/null << 'EOF'
ANTHROPIC_API_KEY=sk-ant-XXXX
OPENCLAW_SECRET=your-secret-string

# S3 backups (if backup.enable = true)
OPENCLAW_S3_ACCESS_KEY_ID=XXXX
OPENCLAW_S3_SECRET_ACCESS_KEY=XXXX
OPENCLAW_S3_BUCKET=openclaw-backups
OPENCLAW_S3_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
EOF
sudo chmod 600 /var/lib/openclaw/secrets/env
```

### 4. Deploy

```bash
sudo nixos-rebuild switch
```

### 5. Verify

```bash
openclaw-status
openclaw-logs
curl http://127.0.0.1:3000/
```

## Key Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable the OpenClaw service |
| `package` | (flake's package) | OpenClaw package to use |
| `pnpmDepsHash` | `lib.fakeHash` | SHA256 hash of pnpm dependencies (set to correct hash after first build) |
| `packageOverride` | `null` | Attrs to override package parameters (e.g., `{ esbuild = pkgs.esbuild.overrideAttrs (...); }`) |
| `user` | `"openclaw"` | System user to run as |
| `group` | `"openclaw"` | System group |
| `dataDir` | `"/var/lib/openclaw"` | Data directory |
| `host` | `"127.0.0.1"` | Bind address |
| `port` | `3000` | Port |
| `environmentFiles` | `[]` | Secret env files |

### Models (`services.openclaw.models.<name>.*`)

| Option | Type | Description |
|--------|------|-------------|
| `type` | enum | Backend: `anthropic`, `openai-compatible`, `ollama`, `rocm`, `remote` |
| `modelName` | string | Model identifier |
| `endpoint` | string | API endpoint (optional) |
| `isDefault` | bool | Set as default model |
| `maxTokens` | null int | Max tokens (optional) |
| `temperature` | null float | Temperature (optional) |
| `extraConfig` | null attrs | Extra config key-values (optional) |

### Git Tracking (`services.openclaw.gitTracking.*`)

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `true` | Enable auto-commit |
| `interval` | `"*:0/5"` | Timer schedule |

### Backup (`services.openclaw.backup.*`)

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable S3-compatible backups |
| `interval` | `"hourly"` | Timer schedule |
| `retentionCount` | `168` | Backups to keep |
| `storageProvider` | `"r2"` | Storage: `r2` (Cloudflare), `s3` (AWS), `minio`, `other` |

### Tuning (`services.openclaw.tuning.*`)

| Option | Default | Description |
|--------|---------|-------------|
| `restart.limitBurst` | `5` | Max restarts before stopping |
| `restart.limitInterval` | `300` | Restart window (seconds) |
| `restart.sec` | `5` | Seconds before restart |
| `resources.maxMemory` | `"8G"` | Memory limit |
| `resources.maxFiles` | `65536` | Max open files |
| `resources.cpuQuota` | `"400%"` | CPU limit (4 cores) |
| `gitTracking.randomDelay` | `30` | Random delay (seconds) |
| `backup.randomDelay` | `300` | Random delay (seconds) |
| `status.logLines` | `25` | Log lines in status |
| `status.gitLogLines` | `10` | Git commits in status |

### Browser (`services.openclaw.browser.*`)

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable browser automation |
| `useVirtualDisplay` | `false` | Use Xvfb instead of headless |
| `displayNumber` | `":99"` | Xvfb display |
| `displayResolution` | `"2560x1440x24"` | Virtual resolution |
| `vncPort` | `5900` | VNC port |
| `vncPassword` | `null` | VNC password (null = no password, local users can connect without auth) |

## Building

The first build will fail with the correct hash for pnpm dependencies. Use the hash from the error message in your configuration:

```nix
services.openclaw.pnpmDepsHash = "sha256-XXXXXXXX";
```

### Overriding the source

To use a different OpenClaw source (local path, fork, etc.):

```bash
# From a local path
nix build .#openclaw --override-input openclaw-src /path/to/openclaw

# From a different repository
nix build .#openclaw --override-input openclaw-src github:username/openclaw
```

### Customizing the package

To override package parameters (like `nodejs`, `esbuild`, `pnpm`, etc.):

```nix
services.openclaw.packageOverride = {
  nodejs = pkgs.nodejs_20;
};
```

Or to override multiple parameters:

```nix
services.openclaw.packageOverride = {
  nodejs = pkgs.nodejs_20;
  esbuild = pkgs.esbuild.override { singleThreaded = true; };
};
```

## CLI Tools

- `openclaw` - Run commands as the openclaw user
- `openclaw-status` - Show service status
- `openclaw-logs` - Follow logs
- `openclaw-git` - Git operations
- `openclaw-backup-now` - Trigger backup
- `openclaw-restore <file>` - Restore from R2

## Home-Manager

For non-root or standalone Home-Manager use (adds options under `services.openclaw`):

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-openclaw.url = "github:your-org/nix-openclaw";
  };

  outputs = { self, nixpkgs, nix-openclaw, home-manager, ... }: {
    homeConfigurations."user@hostname" = home-manager.lib.homeManagerConfiguration {
      modules = [
        nix-openclaw.homeManagerModules.default
        ./home.nix
      ];
    };
  };
}
```

```nix
# home.nix
{ lib, ... }:
{
  services.openclaw = {
    enable = true;
    # ... available options: enable, package, dataDir, host, port,
    #    environmentFiles, extraEnvironment, models, defaultModel,
    #    gitTracking, tuning (restart.sec, gitTracking.randomDelay, status.logLines)
  };
}
```

## Environment Variables

Place in your secrets file (via `environmentFiles`):

| Variable | When needed | Description |
|----------|--------------|-------------|
| `ANTHROPIC_API_KEY` | Anthropic models | Anthropic API key |
| `OPENCLAW_SECRET` | Always | Authentication secret |
| `OPENAI_API_KEY` | OpenAI models | OpenAI API key |
| `ANTHROPIC_BASE_URL` | Custom endpoint | Override Anthropic endpoint |
| `OPENAI_BASE_URL` | Custom endpoint | Override OpenAI endpoint |
| `OPENCLAW_S3_ACCESS_KEY_ID` | `backup.enable = true` | S3 API access key |
| `OPENCLAW_S3_SECRET_ACCESS_KEY` | `backup.enable = true` | S3 API secret |
| `OPENCLAW_S3_BUCKET` | `backup.enable = true` | S3 bucket name |
| `OPENCLAW_S3_ENDPOINT` | `backup.enable = true` | S3 endpoint URL |
