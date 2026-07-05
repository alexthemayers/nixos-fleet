{
  stdenvNoCC,
  lib,
  fetchurl,
  bash,
  coreutils,
  jq,
  gnutar,
  p7zip,
  curl,
  unshield,
  cacert,
  makeWrapper,
  steam-run,
}:

let
  ut2004-data = stdenvNoCC.mkDerivation {
    pname = "ut2004-data";
    version = "1.2.2";

    src = fetchurl {
      url = "https://raw.githubusercontent.com/OldUnreal/FullGameInstallers/master/Linux/install-ut2004.sh";
      sha256 = "1ihxcf1vph8gia634d4pv5ad5gfsip5791dv77zx72yix2nrfyff";
    };

    dontUnpack = true;
    dontFixup = true;

    nativeBuildInputs = [
      bash
      coreutils
      jq
      gnutar
      p7zip
      curl
      unshield
      cacert
    ];

    # Needed for curl to verify SSL certificates during download
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

    buildPhase = ''
      # The script uses XDG base directories and assumes a standard environment.
      export HOME=$TMPDIR

      # Execute the installation script, forcing it to install to $out non-interactively
      set +o pipefail
      yes y | bash $src -d $out --ui-mode none --application-entry skip --desktop-shortcut skip
      set -o pipefail
    '';

    # Fixed-Output Derivation settings
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-fBr8YpaZVNM0IS4SwAHQZxTCfJ8Bm5ZxUjq7hVg0vXQ=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "ut2004";
  version = "1.2.2";

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin

    # Pre-compiled proprietary games often need a traditional FHS environment
    # to find their libraries (like libdl, libpthread, libGL, libopenal). 
    # steam-run provides exactly this environment seamlessly.
    makeWrapper ${steam-run}/bin/steam-run $out/bin/ut2004 \
      --add-flags "${ut2004-data}/System/UT2004"

    # Expose the raw data for convenience
    ln -s ${ut2004-data} $out/data
  '';

  meta = with lib; {
    description = "Unreal Tournament 2004 via OldUnreal Linux Installer";
    homepage = "https://oldunreal.com";
    license = licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
