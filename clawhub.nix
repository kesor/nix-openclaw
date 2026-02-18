{
  lib,
  stdenv,
  nodejs,
  cacert,
}:

stdenv.mkDerivation rec {
  pname = "clawhub";
  version = "0.7.0";

  nativeBuildInputs = [
    nodejs
    cacert
  ];

  dontUnpack = true;

  buildPhase = ''
    export HOME=$TMPDIR
    export npm_config_cache=$TMPDIR/npm-cache
    mkdir -p $npm_config_cache
    npm install --global --prefix=$out clawhub@${version}
  '';

  installPhase = ''
    mkdir -p $out/bin
    for f in $out/lib/node_modules/.bin/*; do
      name=$(basename $f)
      [ ! -e "$out/bin/$name" ] && ln -sf "$f" "$out/bin/$name"
    done
  '';

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = "sha256-gUZVZusfDrIhrns6NdHVwYoljyJqHR50szaVSCy5ldk=";

  meta = {
    description = "ClawHub CLI - install, update, search, and publish agent skills";
    homepage = "https://github.com/openclaw/clawhub";
    license = lib.licenses.mit;
    mainProgram = "clawhub";
  };
}
