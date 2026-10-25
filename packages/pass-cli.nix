{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  # version and hash; update-pass-cli writes this file
  pin = lib.importJSON ./pass-cli.json;
in
stdenv.mkDerivation rec {
  pname = "pass-cli";
  inherit (pin) version;

  src = fetchurl {
    url = "https://github.com/protonpass/pass-cli/releases/download/${version}/pass-cli-linux-x86_64";
    inherit (pin) hash;
  };

  dontUnpack = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/pass-cli
    runHook postInstall
  '';

  meta = {
    description = "Proton Pass command-line interface";
    homepage = "https://github.com/protonpass/pass-cli";
    changelog = "https://github.com/protonpass/pass-cli/releases/tag/${version}";
    license = lib.licenses.gpl3Only;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "pass-cli";
  };
}
