{
  lib,
  fetchPnpmDeps,
  pnpm,
  pnpmConfigHook,
  nodejs,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  version ? "0.3.0",
  hash ? "sha256-qmLSIQJWyTB50YVTUIk4fya9VyHWnhNF0l6l8Pd8rC8=",
  pnpmDepsHash ? "sha256-jDVMymm60F+bFpJiG6G8XH/Ki4DIZyEluRkX+DJuyrY=",
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
    pnpmConfigHook
    nodejs
    makeWrapper
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
      "--no-optional"
      "--config=use-node-version=false"
      "--config=strict-peer-dependencies=false"
      "--config=global-dir=$HOME/.local/share/pnpm"
    ];
    postUnpack = ''
      find source -type f -name package.json -print0 | xargs -0 sed -i \
        -e '/"prepare"/s/".*"/"prepare": "echo skipped husky"/' \
        -e '/"postinstall"/s/".*"/"postinstall": "echo skipped"/' \
        -e '/"prepublishOnly"/s/".*"/"prepublishOnly": "echo skipped"/' || true
    '';
  };

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
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
