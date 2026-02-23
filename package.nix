{
  bun,
  esbuild,
  fetchPnpmDeps,
  lib,
  makeWrapper,
  nodejs ? pkgs.nodejs_22,
  pkgs,
  pnpm,
  pnpmConfigHook,
  pnpmDepsHash ? lib.fakeHash,
  src,
  version ? "0-unstable",
}:

lib.makeOverridable (finalAttrs: {
  pname = "openclaw";
  inherit version src;

  nativeBuildInputs = [
    bun
    makeWrapper
    nodejs
    pnpm
    pnpmConfigHook
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    hash = pnpmDepsHash;
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
