{ lib, pkgs, ... }:

{
  assertions = [
    {
      assertion = lib.versionAtLeast pkgs.rustc.version "1.95";
      message = "El entorno de desarrollo requiere Rust 1.95 o superior.";
    }
  ];

  # Herramientas de desarrollo disponibles directamente en los escritorios.
  # Los devShells del flake siguen permitiendo aislar dependencias por proyecto.
  environment.systemPackages = with pkgs; [
    # Python.
    python3
    python3Packages.pip
    uv
    ruff

    # Rust.
    rustc
    cargo
    rust-analyzer
    rustfmt
    clippy

    # Compilación de extensiones y dependencias nativas.
    gcc
    clang
    mold
    pkg-config
    cmake
    gnumake
  ];
}
