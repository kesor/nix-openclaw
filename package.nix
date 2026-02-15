{
  lib,
  buildNpmPackage,
  nodejs_22,
  makeWrapper,
  src,
  version ? "0-unstable",
  npmDepsHash ? lib.fakeHash,
}:

buildNpmPackage {
  pname = "openclaw";
  inherit version src npmDepsHash;

  nativeBuildInputs = [ makeWrapper ];

  buildPhase = ''
    runHook preBuild
    npm run build || true
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
