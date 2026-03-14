{
  lib,
  fetchPnpmDeps,
  pnpm,
  pnpmConfigHook,
  nodejs,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "acpx";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "acpx";
    tag = "v${finalAttrs.version}";
    hash = "sha256-qmLSIQJWyTB50YVTUIk4fya9VyHWnhNF0l6l8Pd8rC8=";
  };

  nativeBuildInputs = [
    pnpm
    pnpmConfigHook
    nodejs
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-4F2T5dDznY9iV7pR3qLk8jX2mW1sN0tU6oA5vX4cZs=";
    fetcherVersion = 3;
  };

  buildPhase = ''
    pnpm build
  '';

  installPhase = ''
    mkdir -p $out/bin
    ln -sf $out/lib/node_modules/.bin/acpx $out/bin/acpx
  '';

  meta = {
    description = "acpx - ACP client for Agent-to-Agent communication";
    homepage = "https://github.com/openclaw/acpx";
    license = lib.licenses.mit;
    mainProgram = "acpx";
    platforms = lib.platforms.linux;
  };
})
