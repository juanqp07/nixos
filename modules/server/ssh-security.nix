{ ... }:

{
  services = {
    fail2ban = {
      enable = true;

      maxretry = 3;
      bantime = "24h";

      bantime-increment = {
        enable = true;
        rndtime = "15m";
        overalljails = true;
        maxtime = "90d";
        multipliers = "1 2 4 8 16 32 64";
      };

      jails = {
        sshd = {
          enabled = true;

          settings = {
            # El filtro va en settings: jails.<n>.filter de nixpkgs descarta el
            # valor de texto y usaría "sshd" sin el modo aggressive.
            filter = "sshd[mode=aggressive]";
            maxretry = 3;
            findtime = "10m";
          };
        };
      };
    };
    openssh = {
      enable = true;
      settings.PermitRootLogin = "no";
      # Atlas y Pico mantienen el mismo acceso SSH administrativo.
      settings.PasswordAuthentication = true;
    };
  };
}
