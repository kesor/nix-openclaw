{
  lib,
  buildPnpmPackage,
  nodejs_22,
  makeWrapper,
  esbuild,
  bun,
  src,
  version ? "0-unstable",
  pnpmDepsHash ? lib.fakeHash,
}:

buildPnpmPackage {
  pname = "openclaw";
  inherit version src pnpmDepsHash;

  nativeBuildInputs = [ makeWrapper bun ];

  # Provide esbuild from nixpkgs
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
      --add-flags "$out/lib/openclaw/dist/index.js" \
      --set NODE_ENV production
    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenClaw – AI-powered application";
    platforms = platforms.linux;
    mainProgram = "openclaw";
  };
}
