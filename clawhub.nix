{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  nodejs,
}:
let
  version = "0.7.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/clawhub/-/clawhub-${version}.tgz";
    hash = "sha256-hKCAFLSuifOi2jQqUsDn7liv4u2+PyulYsKXyCizruA=";
  };

  # Install dependencies with npm in a fixed-output derivation
  nodeModules = stdenv.mkDerivation {
    pname = "clawhub-node-modules";
    inherit version src;

    nativeBuildInputs = [ nodejs ];

    dontPatchShebangs = true;

    buildPhase = ''
      export HOME=$TMPDIR
      npm install --omit=dev --ignore-scripts --no-audit --no-fund
    '';

    installPhase = ''
      mkdir -p $out
      cp -r node_modules $out/
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = lib.fakeHash;
  };

in
stdenv.mkDerivation rec {
  pname = "clawhub";
  inherit version src;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [ nodejs ];

  postPatch = ''
    patchShebangs bin/clawdhub.js
  '';

  installPhase = ''
    mkdir -p $out/lib/node_modules/clawhub
    cp -r . $out/lib/node_modules/clawhub
    cp -r ${nodeModules}/node_modules $out/lib/node_modules/clawhub/

    mkdir -p $out/bin
    makeWrapper $out/lib/node_modules/clawhub/bin/clawdhub.js $out/bin/clawhub \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}
    ln -s $out/bin/clawhub $out/bin/clawdhub
  '';

  meta = {
    description = "ClawHub CLI - install, update, search, and publish agent skills";
    homepage = "https://github.com/openclaw/clawhub";
    license = lib.licenses.mit;
    mainProgram = "clawhub";
  };
}
