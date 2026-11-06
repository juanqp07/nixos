{ ... }:

{
  # Home Manager se integra en la generación de NixOS y reutiliza el pkgs del host.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    # Evita sobrescribir configuraciones preexistentes sin copia de seguridad.
    backupFileExtension = "hm-backup";

    users.juan = import ../home/juan;
  };
}
