{ lib, appimageTools, fetchurl }:

let
  pname = "nori";
  version = "0.8.0";

  src = fetchurl {
    url = "https://github.com/norifm/nori/releases/download/v${version}/nori-desktop-${version}-linux-x86_64.AppImage";
    hash = "sha256-6Es8SDpk3tMDTUZIvzwhnNi4CdH+atMxYi08DnJrv+4=";
  };
in
appimageTools.wrapType2 (finalAttrs: {
  inherit pname version src;

  # Nori deliberately uses the host WebKitGTK instead of bundling it.
  extraPkgs = pkgs: [
    pkgs.webkitgtk_4_1
  ];

  extraInstallCommands = ''
    install -Dm444 "${finalAttrs.contents}/dev.nori.desktop.desktop" \
      "$out/share/applications/dev.nori.desktop.desktop"
    substituteInPlace "$out/share/applications/dev.nori.desktop.desktop" \
      --replace-fail 'Exec=nori-desktop' 'Exec=nori'

    install -Dm444 "${finalAttrs.contents}/nori.png" \
      "$out/share/icons/hicolor/512x512/apps/nori.png"
  '';

  meta = {
    description = "Music player for your own server";
    homepage = "https://norifm.com/";
    license = lib.licenses.agpl3Plus;
    mainProgram = "nori";
    platforms = [ "x86_64-linux" ];
  };
})
