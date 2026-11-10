{ config, lib, ... }:

let
  cfg = config.services.sunshine-kms;
in
{
  options.services.sunshine-kms.enable =
    lib.mkEnableOption "Sunshine KMS access to the SDDM Wayland greeter before login";

  config = lib.mkIf cfg.enable {
    # Reuse the supported NixOS Sunshine package and its CAP_SYS_ADMIN wrapper.
    # KMS is explicit: automatic capture may choose a session-bound backend.
    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = false;

      settings = {
        capture = "kms";
        port = 47989;
        system_tray = "disabled";
        upnp = "disabled";

        # "wan" is required for the remote Web UI. Reachability is restricted
        # below to NetBird; NetBird ACLs and a strong Web UI password still apply.
        origin_web_ui_allowed = "wan";
      };
    };

    # The greeter must itself run on Wayland for this deployment.
    services.displayManager.sddm.wayland.enable = lib.mkForce true;

    # Start juan's user manager at boot, even with no graphical login.
    users.users.juan.linger = true;

    # Keep the capability-bearing wrapper executable only by root and the
    # dedicated sunshine-kms group. The NixOS default also permits "other".
    users.groups.sunshine-kms = { };
    users.users.juan.extraGroups = [ "sunshine-kms" ];
    security.wrappers.sunshine = {
      group = lib.mkForce "sunshine-kms";
      permissions = lib.mkForce "u+rx,g+x,o-rwx";
    };

    # Sunshine only needs its virtual input node. Do not add juan to the broad
    # "input" group, which can grant read access to physical keyboard devices.
    # This later local rule overrides Sunshine's packaged GROUP="input" rule.
    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
      KERNEL=="uhid", MODE="0660", GROUP="uinput"
    '';

    # NixOS normally ties its user service to graphical-session.target. Move
    # it to default.target and detach it from the graphical session so it is
    # already available at SDDM and survives logout. Lingering makes
    # default.target start at boot. The service still runs as juan; only the
    # NixOS security wrapper grants the CAP_SYS_ADMIN needed by KMS.
    systemd.user.services.sunshine = {
      wantedBy = lib.mkForce [ "default.target" ];
      partOf = lib.mkForce [ ];
      wants = lib.mkForce [ ];
      after = lib.mkForce [ ];
      unitConfig.ConditionUser = "juan";
    };

    # Moonlight traffic and the Web UI are accepted only through NetBird.
    # Do not use services.sunshine.openFirewall, which opens ports globally.
    networking.firewall.interfaces.wt0 = {
      allowedTCPPorts = [
        47984
        47989
        47990
        48010
      ];

      allowedUDPPorts = [
        47998
        47999
        48000
        48002
        48010
      ];
    };
  };
}
