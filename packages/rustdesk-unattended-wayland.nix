{ lib
, stdenvNoCC
, fetchurl
, dpkg
, buildFHSEnv
, appimageTools
}:

let
  version = "1.5.1";

  # Official RustDesk nightly preview, published 2026-11-06.
  # The hash is pinned so the build never follows a moving nightly artifact.
  deb = stdenvNoCC.mkDerivation {
    pname = "rustdesk-unattended-wayland-deb";
    inherit version;

    src = fetchurl {
      url = "https://github.com/rustdesk/rustdesk/releases/download/nightly/rustdesk-unattended-wayland-1.5.1-x86_64.deb";
      hash = "sha256-UvJwKbAAIsRLq/yXBo8SUdZ9jDauWeeHVCPbnoJYuvA=";
    };

    nativeBuildInputs = [ dpkg ];
    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      dpkg-deb --extract "$src" "$out"

      test -x "$out/usr/share/rustdesk/rustdesk"
      test -e "$out/usr/lib/rustdesk/libdrmtap.so.0"

      # Match the upstream build checks: reject a CPU-only libdrmtap stub.
      drmtap="$out/usr/lib/rustdesk/libdrmtap.so.0"
      grep -a -qF 'libEGL.so.1' "$drmtap"
      grep -a -qF 'eglCreateImageKHR' "$drmtap"

      # Match the upstream assertion that the unused privileged helper path
      # and its socketpair transport are absent from the library.
      if grep -a -qF 'socketpair' "$drmtap" || grep -a -qF '/usr/libexec/drmtap-helper' "$drmtap"; then
        echo "Unexpected privileged drmtap helper path in the bundled library" >&2
        exit 1
      fi
      runHook postInstall
    '';
  };

  fhsDefaults = appimageTools.defaultFhsEnvArgs;
in
buildFHSEnv (fhsDefaults // {
  pname = "rustdesk-unattended-wayland";
  inherit version;
  executableName = "rustdesk-unattended-wayland";

  # Execute the upstream binary within a standard FHS layout. RustDesk's DRM
  # loader deliberately uses /usr/lib/rustdesk/libdrmtap.so.0; the FHS root
  # provides that path without adding a global ld.so.conf entry on NixOS.
  runScript = "/usr/bin/rustdesk";

  targetPkgs = pkgs: fhsDefaults.targetPkgs pkgs ++ (with pkgs; [
    xdotool
    systemd
    libayatana-appindicator
  ]);

  multiPkgs = pkgs: fhsDefaults.multiPkgs pkgs ++ (with pkgs; [
    libva
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
  ]);

  extraBuildCommands = ''
    # buildFHSEnv already creates usr/lib as a symlink to usr/lib64.
    mkdir -p "$out/usr/share" "$out/usr/bin"
    ln -s "${deb}/usr/share/rustdesk" "$out/usr/share/rustdesk"
    ln -s "${deb}/usr/lib/rustdesk" "$out/usr/lib/rustdesk"
    ln -s "${deb}/usr/share/rustdesk/rustdesk" "$out/usr/bin/rustdesk"

    test -x "$out/usr/bin/rustdesk"
    test -e "$out/usr/lib/rustdesk/libdrmtap.so.0"
  '';

  meta = {
    description = "Official RustDesk unattended Wayland preview, wrapped for NixOS";
    homepage = "https://rustdesk.com/blog/unattended-remote-access-wayland/";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "rustdesk-unattended-wayland";
  };
})
