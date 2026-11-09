{
  lib,
  appimageTools,
  fetchurl,
  nix-update-script,
  stdenv,
}:

let
  assets = {
    "x86_64-linux" = {
      arch = "x86_64";
      hash = "sha256-6Es8SDpk3tMDTUZIvzwhnNi4CdH+atMxYi08DnJrv+4=";
    };
    "aarch64-linux" = {
      arch = "aarch64";
      hash = "sha256-u+nQFJ6Nd6cWRSmsoSGc2AtARI0qxWKqrecL0IU9wBg=";
    };
  };

  asset = assets.${stdenv.hostPlatform.system} or (throw "Nori is not supported on ${stdenv.hostPlatform.system}");
in
appimageTools.wrapType2 (finalAttrs: {
  pname = "nori";
  version = "0.8.0";

  src = fetchurl {
    url = "https://github.com/norifm/nori/releases/download/v${finalAttrs.version}/nori-desktop-${finalAttrs.version}-linux-${asset.arch}.AppImage";
    inherit (asset) hash;
  };

  # Nori intentionally uses the host WebKitGTK for its sign-in window.
  extraPkgs = pkgs: [ pkgs.webkitgtk_4_1 ];

  extraInstallCommands = ''
    install -Dm444 "${finalAttrs.contents}/dev.nori.desktop.desktop" \
      "$out/share/applications/dev.nori.desktop.desktop"
    substituteInPlace "$out/share/applications/dev.nori.desktop.desktop" \
      --replace-fail 'Exec=nori-desktop' 'Exec=nori'

    install -Dm444 "${finalAttrs.contents}/nori.png" \
      "$out/share/icons/hicolor/512x512/apps/nori.png"
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Music player for Navidrome, Subsonic and YouTube Music";
    homepage = "https://norifm.com/";
    changelog = "https://github.com/norifm/nori/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Plus;
    maintainers = [ lib.maintainers.juanqp07 ];
    mainProgram = "nori";
    platforms = builtins.attrNames assets;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
