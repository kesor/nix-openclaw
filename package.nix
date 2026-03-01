{
  bun,
  esbuild,
  fetchPnpmDeps,
  git,
  lib,
  makeWrapper,
  nodejs ? pkgs.nodejs_22,
  pkgs,
  pnpm,
  pnpmConfigHook,
  pnpmDepsHash ? lib.fakeHash,
  src,
  stdenv,
  version ? "0-unstable",
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "openclaw";
  inherit version src;

  nativeBuildInputs = [
    bun
    git
    makeWrapper
    nodejs
    pnpm
    pnpmConfigHook
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    hash = pnpmDepsHash;
    fetcherVersion = 3;
    preConfigure = ''
      export HOME=$(mktemp -d -p "$TMPDIR" pnpm-home.XXXXXX)
      mkdir -p "$HOME/.local/share/pnpm" "$HOME/.cache/pnpm" "$HOME/.config"
      export PNPM_HOME="$HOME/.local/share/pnpm"
      export PATH="$PNPM_HOME:$PATH"
      # Critical: tell pnpm NOT to manage its own binary
      export COREPACK_NPM_REGISTRY="https://registry.npmjs.org"
      pnpm config set --location project node-linker hoisted
      pnpm config set --location project shamefully-hoist true
      pnpm config set package-import-method copy
    '';
    installFlags = [ "--ignore-scripts" ];
    extraArgs = [
      "--ignore-scripts"
      "--frozen-lockfile"
      "--prefer-offline"
      "--no-optional" # skip optional deps that might trigger tools
      "--config=use-node-version=false" # try to avoid version switching
      "--config=strict-peer-dependencies=false"
      "--config=global-dir=$HOME/.local/share/pnpm"
    ];
    postUnpack = ''
      find source -type f -name package.json -print0 | xargs -0 sed -i \
        -e '/"prepare"/s/".*"/"prepare": "echo skipped husky"/' \
        -e '/"postinstall"/s/".*"/"postinstall": "echo skipped"/' \
        -e '/"prepublishOnly"/s/".*"/"prepublishOnly": "echo skipped"/' || true
      find source -type f -path '*/node_modules/husky/*.js' -exec sed -i 's/git/echo skipped git/g' {} + || true
    '';
  };

  ESBUILD_BINARY_PATH = "${esbuild}/bin/esbuild";
  OPENCLAW_PREFER_PNPM = "1";

  buildPhase = ''
    runHook preBuild
    pnpm build
    pnpm ui:build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/openclaw
    cp -r . $out/lib/openclaw/

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/openclaw \
      --add-flags "$out/lib/openclaw/openclaw.mjs" \
      --set NODE_ENV production

    makeWrapper ${nodejs}/bin/node $out/bin/openclaw-gateway \
      --add-flags "$out/lib/openclaw/openclaw.mjs" \
      --add-flags "gateway" \
      --set NODE_ENV production
    runHook postInstall
  '';

  meta = {
    description = "OpenClaw – AI-powered application";
    platforms = lib.platforms.linux;
    mainProgram = "openclaw";
  };
})
