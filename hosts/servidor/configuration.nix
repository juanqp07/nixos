{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "servidor-jqp";

  # --- DOCKER (Específico del servidor) ---
  virtualisation.docker.enable = true;
  virtualisation.docker.autoPrune.enable = true; # Limpiar imágenes viejas solo
  
  # Añadir usuario al grupo docker para no usar sudo siempre
  users.users.juan.extraGroups = [ "docker" ];

  # --- SIN ENTORNO GRÁFICO ---
  # Al no importar desktop-gaming.nix, NixOS arranca en modo texto (TTY)
  # que es lo correcto para un servidor.

  # --- ACCESO REMOTO (SSH) ---
  # Vital para un servidor sin pantalla
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true; # O false si usas llaves SSH (recomendado)
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
