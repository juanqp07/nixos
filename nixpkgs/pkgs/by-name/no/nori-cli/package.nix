{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  gnutar,
  gzip,
  buildFHSEnv,
  appimageTools,
  alsa-lib,
  webkitgtk_4_1,
  cacert,
  nix-update-script,
}:

let
  version = "0.8.0";

  assets = {
    "x86_64-linux" = {
      arch = "x86_64";
      hash = "sha256-lc7VlWSjBM/EHO2HcAkkreBaJFvJwy3ymhDdxbUt+kk=";
    };
    "aarch64-linux" = {
      arch = "aarch64";
      hash = "sha256-fNI2oxNBDr/wEKeNIsoFVW3xE0/pcNQMhsy6UU+hFbQ=";
    };
  };

  asset = assets.${stdenv.hostPlatform.system} or (throw "Nori CLI is not supported on ${stdenv.hostPlatform.system}");

  src = fetchurl {
    url = "https://github.com/norifm/nori/releases/download/v${version}/nori-cli-${version}-linux-${asset.arch}.tar.gz";
    inherit (asset) hash;
  };

  unpacked = stdenvNoCC.mkDerivation {
    pname = "nori-cli-unpacked";
    inherit version src;

    dontUnpack = true;
    nativeBuildInputs = [ gnutar gzip ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$TMPDIR/nori-cli" "$out/bin"
      tar -xzf "$src" -C "$TMPDIR/nori-cli"

      binary="$(find "$TMPDIR/nori-cli" -type f -name nori-cli -print -quit)"
      test -n "$binary"
      install -m755 "$binary" "$out/bin/nori-cli"

      runHook postInstall
    '';
  };

  fhsDefaults = appimageTools.defaultFhsEnvArgs;
in
buildFHSEnv (fhsDefaults // {
  pname = "nori-cli";
  inherit version;

  executableName = "nori-cli";
  runScript = "${unpacked}/bin/nori-cli";

  targetPkgs = pkgs:
    fhsDefaults.targetPkgs pkgs
    ++ [
      alsa-lib
      webkitgtk_4_1
    ];

  profile = ''
    export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Terminal music player for Navidrome, Subsonic and YouTube Music";
    homepage = "https://norifm.com/";
    changelog = "https://github.com/norifm/nori/releases/tag/v${version}";
    license = lib.licenses.agpl3Plus;
    maintainers = [ lib.maintainers.juanqp07 ];
    mainProgram = "nori-cli";
    platforms = builtins.attrNames assets;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
