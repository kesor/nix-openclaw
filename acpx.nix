{
  lib,
  stdenv,
  nodejs,
  cacert,
}:

stdenv.mkDerivation rec {
  pname = "acpx";
  version = "0.0.0";

  nativeBuildInputs = [
    nodejs
    cacert
  ];

  dontUnpack = true;

  buildPhase = ''
    export HOME=$TMPDIR
    export npm_config_cache=$TMPDIR/npm-cache
    mkdir -p $npm_config_cache
    npm install --global --prefix=$out acpx@latest
  '';

  installPhase = ''
    mkdir -p $out/bin
    for f in $out/lib/node_modules/.bin/*; do
      name=$(basename $f)
      [ ! -e "$out/bin/$name" ] && ln -sf "$f" "$out/bin/$name"
    done
  '';

  meta = {
    description = "acpx - ACP client for Agent-to-Agent communication";
    homepage = "https://github.com/openclaw/acpx";
    license = lib.licenses.mit;
    mainProgram = "acpx";
    platforms = lib.platforms.linux;
  };
}
