{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  pin = lib.importJSON ./pass-cli.json;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "pass-cli";
  inherit (pin) version;

  src = fetchurl {
    url = "https://github.com/protonpass/pass-cli/releases/download/${finalAttrs.version}/pass-cli-linux-x86_64";
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
    changelog = "https://github.com/protonpass/pass-cli/releases/tag/${finalAttrs.version}";
    license = lib.licenses.gpl3Only;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "pass-cli";
  };
})
