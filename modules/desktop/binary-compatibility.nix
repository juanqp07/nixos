{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  # NIX-LD: COMPATIBILIDAD CON BINARIOS LINUX
  # ============================================================

  programs.nix-ld.enable = true;

  programs.nix-ld.libraries = with pkgs; [
    # Runtime y bibliotecas básicas.
    stdenv.cc.cc
    glibc
    zlib
    libz
    bzip2
    xz
    zstd
    lz4
    libgcc

    # Seguridad y certificados.
    curl
    openssl
    nss
    nspr

    # Fuentes y renderizado de texto.
    fontconfig
    freetype
    fribidi
    harfbuzz
    pango
    libthai
    libdatrie
    expat
    libxml2
    icu

    # GTK y bibliotecas gráficas.
    glib
    gtk3
    gtk4
    gdk-pixbuf
    cairo
    atk
    at-spi2-atk
    at-spi2-core
    libepoxy

    # Audio.
    alsa-lib
    pipewire
    libpulseaudio
    libsndfile
    libsamplerate

    # X11.
    libx11
    libxext
    libxrandr
    libxrender
    libxi
    libxfixes
    libxcursor
    libxinerama
    libxcomposite
    libxdamage
    libxscrnsaver
    libxtst
    libxkbcommon
    libxkbfile

    # XCB.
    libxcb
    libxcb-util
    libxcb-wm
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-cursor

    # Wayland.
    wayland

    # OpenGL, Vulkan y vídeo.
    libGL
    libGLU
    mesa
    vulkan-loader
    libdrm
    libgbm
    ffmpeg
    libva
    libvdpau

    # Sistema de archivos y dispositivos.
    fuse3
    libarchive
    libffi
    libcap
    libuuid
    libusb1
    sqlite
    dbus
    libgpg-error
    e2fsprogs

    # Herramientas de compilación.
    gnumake
    gcc
    python3

    # Entornos de desarrollo.
    nodejs_24
    deno
    bun
    rustc
    cargo
    rustfmt
    clippy
  ];

  # ============================================================

}
