{
  lib,
  stdenv,
  nodejs_22,
  pnpm,
  makeWrapper,
  esbuild,
  bun,
  src,
  version ? "0-unstable",
  pnpmDepsHash ? lib.fakeHash,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "openclaw";
  inherit version src;

  nativeBuildInputs = [
    nodejs_22
    pnpm.configHook
    makeWrapper
    bun
  ];

  pnpmDeps = pnpm.fetchDeps {
    inherit (finalAttrs) pname version src;
    hash = pnpmDepsHash;
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
    makeWrapper ${nodejs_22}/bin/node $out/bin/openclaw \
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
