_: {
  # SOPS-nix usa la clave privada Ed25519 del host SSH como identidad age.
  # El destinatario público correspondiente se obtiene con ssh-to-age y se
  # registra en .sops.yaml cuando se incorporen secretos cifrados.
  # No se configura una ruta de clave privada dentro del almacén Nix.
  sops.age.sshKeyPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];
}
