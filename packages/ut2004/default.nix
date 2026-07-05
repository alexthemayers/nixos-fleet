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
}:

stdenvNoCC.mkDerivation {
  pname = "ut2004";
  version = "1.2.2";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/OldUnreal/FullGameInstallers/master/Linux/install-ut2004.sh";
    sha256 = "1ihxcf1vph8gia634d4pv5ad5gfsip5791dv77zx72yix2nrfyff";
  };

  dontUnpack = true;

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

        # The script should extract the game data directly into $out
        # Create a bin wrapper for easy execution if the script didn't already create a global-friendly one
        mkdir -p $out/bin
        if [ -f $out/ut2004 ]; then
          ln -s $out/ut2004 $out/bin/ut2004
        else
          # Fallback if the launch script is named differently or placed in System/
          cat > $out/bin/ut2004 <<EOF
    #!/bin/sh
    exec $out/System/ut2004-bin "\$@"
    EOF
          chmod +x $out/bin/ut2004
        fi
  '';

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = "sha256-6IEBJCvDkP+Jn8vG2UlOCyEeUw1tS3VdPVlnEFm2FUs=";

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
