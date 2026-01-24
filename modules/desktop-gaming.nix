{ config, pkgs, ... }:

{
  # --- KERNEL ---
  # Esto activará el kernel Zen
  boot.kernelPackages = pkgs.linuxPackages_zen;
  # --- ENTORNO GRÁFICO (Plasma 6) ---
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb = { layout = "es"; variant = ""; };
  console.keyMap = "es";
  # --- Cloudflare WARP ---
  services.cloudflare-warp.enable = true;
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
    vlc mpv
    windsurf podman-compose
    gearlever cloudflare-warp
    rustdesk-flutter
    go antigravity gcc cmake ffmpeg yt-dlp
  ];
  

  # --- VIRTUALIZACION ---
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  boot.blacklistedKernelModules = [ "kvm-intel" "kvm-amd" ];
  
  # --- USUARIO ---
  users.users.juan = {
    isNormalUser = true;
    extraGroups = [ "wheel" "podman" "vboxusers" "video" ];
  # Esto es lo más importante:
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
};
}
