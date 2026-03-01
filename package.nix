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
    installFlags = [ "--ignore-scripts" ];
    preInstall = ''
      pnpm config set package-import-method copy
    '';
    fetcherVersion = 3;
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
