{ config, pkgs, ... }:

{
  # --- ENTORNO GRÁFICO (Plasma 6) ---
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb = { layout = "es"; variant = ""; };
  console.keyMap = "es";

  # --- SONIDO (Pipewire) ---
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # --- VIRTUALBOX ---
  virtualisation.virtualbox.host.enable = true;
  virtualisation.virtualbox.host.enableExtensionPack = true;  
  virtualisation.virtualbox.guest.enable = true;
  virtualisation.virtualbox.guest.dragAndDrop = true;

  # --- GAMING & APPS ---
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
  programs.gamemode.enable = true;
  services.flatpak.enable = true;
  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    firefox discord vesktop heroic
    supersonic-wayland boxbuddy
    onlyoffice-desktopeditors
    kdePackages.kate gedit
    distrobox vscode    
    netbird-ui
  ];
  

  # --- VIRTUALIZACION ---
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  
  users.users.juan.extraGroups = [ "video" "vboxusers" ];
}
