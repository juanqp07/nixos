{ config, lib, pkgs, ... }:

let
  rustdeskUnattendedWayland =
    pkgs.callPackage ../packages/rustdesk-unattended-wayland.nix { };
in
{
  options.services.rustdesk-unattended-wayland.enable =
    lib.mkEnableOption "RustDesk DRM/KMS unattended access to the Wayland greeter";

  config = lib.mkIf config.services.rustdesk-unattended-wayland.enable {
    # The preview is packaged separately because it captures the active scanout
    # without an xdg-desktop-portal consent dialog. Keep the ordinary RustDesk
    # package and its X11 fallback untouched.
    environment.systemPackages = [ rustdeskUnattendedWayland ];

    # DRM/KMS capture is designed for Wayland greeters and logged-out sessions.
    services.displayManager.sddm.wayland.enable = lib.mkForce true;

    # Keep the existing system service, permissions and shutdown behaviour;
    # only replace its executable with the pinned FHS-wrapped preview build.
    systemd.services.rustdesk.serviceConfig.ExecStart =
      lib.mkForce "${rustdeskUnattendedWayland}/bin/rustdesk-unattended-wayland --service";
  };
}
