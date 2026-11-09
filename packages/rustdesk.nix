{ lib, rustdesk-flutter, fetchFromGitHub, xdotool }:

# Nixpkgs aún fija RustDesk en 1.5.0. Mantener la versión estable actual
# explícita evita esperar a que el paquete llegue a nixpkgs-unstable.
rustdesk-flutter.overrideAttrs (old: rec {
  version = "1.5.1";

  src = fetchFromGitHub {
    owner = "rustdesk";
    repo = "rustdesk";
    tag = version;
    fetchSubmodules = true;
    hash = lib.fakeHash; # Sustituir por el hash verificado tras la primera build.
  };

  cargoHash = lib.fakeHash; # Sustituir por el hash verificado de las dependencias Cargo.

  # RustDesk carga libxdo dinámicamente desde su servidor de sistema.
  # La ruta absoluta evita depender de LD_LIBRARY_PATH global.
  postPatch = (old.postPatch or "") + ''
    substituteInPlace ../libs/libxdo-sys-stub/src/lib.rs \
      --replace-fail 'const LIB_NAMES: [&str; 3] = ["libxdo.so.4", "libxdo.so.3", "libxdo.so"];' \
      'const LIB_NAMES: [&str; 4] = ["${xdotool}/lib/libxdo.so.4", "libxdo.so.4", "libxdo.so.3", "libxdo.so"];'
  '';
})
