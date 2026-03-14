{
  lib,
  stdenv,
  fetchurl,
  nodejs,
  hash ? null,
}:

let
  version = "0.3.0";
  # Fetch from npm registry - hash will be computed by nix if not provided
  tarball = fetchurl {
    url = "https://registry.npmjs.org/acpx/-/acpx-${version}.tgz";
    sha256 = hash;
  };
in

stdenv.mkDerivation rec {
  pname = "acpx";
  inherit version;

  nativeBuildInputs = [ nodejs ];

  src = tarball;

  unpackPhase = ''
    mkdir -p $out/lib/node_modules
    tar -xzf $src -C $out/lib/node_modules
  '';

  installPhase = ''
    mkdir -p $out/bin
    if [ -d "$out/lib/node_modules/.bin" ]; then
      for f in $out/lib/node_modules/.bin/*; do
        name=$(basename $f)
        [ ! -e "$out/bin/$name" ] && ln -sf "$f" "$out/bin/$name"
      done
    fi
  '';

  meta = {
    description = "acpx - ACP client for Agent-to-Agent communication";
    homepage = "https://github.com/openclaw/acpx";
    license = lib.licenses.mit;
    mainProgram = "acpx";
    platforms = lib.platforms.linux;
  };
}
