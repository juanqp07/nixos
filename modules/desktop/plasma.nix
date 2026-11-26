{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  # ENTORNO GRÁFICO (Plasma 6)
  # ============================================================

  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "es";
    variant = "";
  };

  # KDE Plasma 6 como único entorno gráfico, con SDDM como gestor de inicio.
  services.displayManager.sddm.enable = true;

  services.desktopManager.plasma6.enable = true;

  # Electron/Chromium usa Ozone nativo en las sesiones Plasma Wayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Discover se instala automáticamente al habilitar Flatpak/fwupd en Plasma.
  # No lo necesitamos: las aplicaciones Flatpak se gestionan declarativamente.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    discover
  ];

  # Preferencias y alias personales del escritorio gestionados por Home Manager.
  # Este módulo solo se añade a Elytra y Titan desde el Flake.
  home-manager.users.juan.imports = [
    ../../home/juan/desktop.nix
  ];

  programs.kdeconnect.enable = true;

  # Compartir archivos entre dispositivos de la red local.
  # El módulo nativo instala LocalSend y abre TCP/UDP 53317 en el firewall.
  programs.localsend.enable = true;

  # Montaje automático de unidades extraíbles (USB, incluida PS Vita con VitaShell).
  services.udisks2.enable = true;

  # Descubrimiento de dispositivos locales (Chromecast, Google Cast, etc.).
  # Este módulo se importa tanto en Elytra como en Titan.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;

    # Publicación mDNS explícita con las opciones actuales de Avahi.
    settings.publish = {
      "disable-publishing" = false;
      disable-user-service-publishing = false;
      publish-addresses = true;
    };
  };

  # Stremio: el Chromecast recibe el vídeo desde el servidor local del PC.
  # 11470 = HTTP y 12470 = HTTPS. No configurar port forwarding en el router.
  networking.firewall.allowedTCPPorts = [
    11470
    12470
  ];

  # ============================================================

}
