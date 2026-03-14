{
  lib,
  pnpm,
  nodejs,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  version ? "0.3.0",
  hash ? "sha256-qmLSIQJWyTB50YVTUIk4fya9VyHWnhNF0l6l8Pd8rC8=",
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "acpx";
  inherit version;

  src = fetchFromGitHub {
    inherit hash;
    owner = "openclaw";
    repo = "acpx";
    tag = "v${version}";
  };

  nativeBuildInputs = [
    pnpm
    nodejs
    makeWrapper
  ];

  buildPhase = ''
    export HOME=$TMPDIR
    export PNPM_HOME=$TMPDIR/pnpm
    mkdir -p $PNPM_HOME
    export PATH=$PNPM_HOME:$PATH
    pnpm install --frozen-lockfile
    pnpm build
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp -r . $out/lib/acpx
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/acpx --add-flags "$out/lib/acpx/dist/cli.js"
    runHook postInstall
  '';

  meta = {
    description = "acpx - ACP client for Agent-to-Agent communication";
    homepage = "https://github.com/openclaw/acpx";
    license = lib.licenses.mit;
    mainProgram = "acpx";
    platforms = lib.platforms.linux;
  };
})
