{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation rec {
  pname = "pass-cli";
  version = "2.4.2";

  src = fetchurl {
    url = "https://github.com/protonpass/pass-cli/releases/download/${version}/pass-cli-linux-x86_64";
    hash = "sha256-QIm99ZgRQKxb7mXS15v5h2dTf1TTMZe3nl+GxjBxSEI=";
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
