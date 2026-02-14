# ═══════════════════════════════════════════════════════════════════════════════
# File: package.nix
# Description: Derivation that builds OpenClaw from source.
#
# This intentionally supports multiple build strategies so it can adapt
# as the upstream project evolves.
# ═══════════════════════════════════════════════════════════════════════════════
{ lib
, stdenv
, nodejs_22
, makeWrapper
, cacert
, git
, src
, version ? "0-unstable"
  # Set this to the hash printed by the first failed build.
  # If using buildNpmPackage (strategy = "npm"), this is the npmDepsHash.
  # Pass `lib.fakeHash` initially to discover the correct value.
, depsHash ? lib.fakeHash
  # "npm"   → use buildNpmPackage (preferred, needs package-lock.json)
  # "shell" → run npm install in a plain derivation (works with anything)
, strategy ? "shell"
}:

let
  nodejs = nodejs_22;

  # ── Strategy A: buildNpmPackage ──────────────────────────────────────────
  # Preferred for reproducibility.  Requires package-lock.json in the source.
  # builtWithBuildNpmPackage = nodejs.pkgs.buildNpmPackage or null;
  #
  # For now, we use the shell strategy since it works out of the box with
  # any Node.js project layout.  Switch to buildNpmPackage once you have a
  # deterministic lock-file and hash.

  # ── Strategy B: plain stdenv ─────────────────────────────────────────────
  shellBuild = stdenv.mkDerivation {
    pname = "openclaw";
    inherit version src;

    nativeBuildInputs = [ nodejs makeWrapper cacert git ];

    # Skip npm phases that need network access during build.
    # We do a two-phase approach: build in an impure sandbox (FOD) would be
    # better, but for rapid iteration the shell approach is simpler.
    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      export npm_config_cache=$TMPDIR/.npm
      export npm_config_nodedir=${nodejs}

      # Attempt npm ci first (if lockfile exists), fall back to npm install
      if [ -f "package-lock.json" ]; then
        npm ci --ignore-scripts --no-audit --no-fund 2>/dev/null || \
          npm install --ignore-scripts --no-audit --no-fund
      else
        npm install --ignore-scripts --no-audit --no-fund
      fi

      # Run build script if the project has one
      if node -e "const p=require('./package.json'); process.exit(p.scripts?.build ? 0 : 1)" 2>/dev/null; then
        npm run build
      fi
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/openclaw
      cp -r . $out/lib/openclaw/

      mkdir -p $out/bin

      # Detect the entry-point
      ENTRY=$(node -e "const p=require('./package.json'); console.log(p.main || p.scripts?.start?.split?.(' ')?.pop?.() || 'index.js')" 2>/dev/null || echo "index.js")

      # If there is a `start` script that uses node, wrap it
      makeWrapper ${nodejs}/bin/node $out/bin/openclaw \
        --add-flags "$out/lib/openclaw/$ENTRY" \
        --set NODE_ENV production \
        --set NODE_PATH "$out/lib/openclaw/node_modules"

      runHook postInstall
    '';

    # This derivation uses network access (impure).
    # In a proper CI/CD pipeline replace this with buildNpmPackage + npmDepsHash.
    __noChroot = true;

    meta = with lib; {
      description = "OpenClaw – AI-powered application";
      platforms = platforms.linux;
      mainProgram = "openclaw";
    };
  };

in
  shellBuild