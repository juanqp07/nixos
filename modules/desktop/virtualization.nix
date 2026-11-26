{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{
  # VIRTUALIZACIÓN: DOCKER + KVM + LIBVIRT
  # ============================================================

  # Docker como backend principal para los contenedores.
  # Distrobox sigue funcionando con Docker.
  virtualisation.docker.enable = true;

  # Máquinas virtuales mediante QEMU/KVM y libvirt.
  virtualisation.libvirtd = {
    enable = true;

    # Arranca bajo demanda (socket activation).
    # Contenedores con --restart=always no arrancan solos al iniciar.
    onBoot = "ignore";
  };

  #virtualisation.virtualbox.host.enable = true;
  #users.extraGroups.vboxusers.members = [ "juan" ];

  # --- PERMISOS DE USUARIO ---
  users.users.juan.extraGroups = [
    "video"
    "audio"
    "lp"
    "scanner"
    "docker"
    "libvirtd"
    "uinput"
    "render"
  ];

  # ============================================================

}
