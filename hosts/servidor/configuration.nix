{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "servidor-jqp";

  # --- DOCKER (Específico del servidor) ---
  virtualisation.docker.enable = true;
  virtualisation.docker.autoPrune.enable = true; # Limpiar imágenes viejas solo
  
  # Añadir usuario al grupo docker para no usar sudo siempre
  users.users.juan.extraGroups = [ "docker" ];


  # --- ACCESO REMOTO (SSH) ---
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };
  
  # Firewall: Abrir puerto SSH (22) y el de Docker si hace falta
  networking.firewall.allowedTCPPorts = [ 22 ];

  # --- DRIVERS INTEL (Transcodificación Servidor) ---
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
    ];
  };
  
  # Gestión de energía servidor
  services.tlp.enable = true;
}
