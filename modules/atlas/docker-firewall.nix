{ pkgs, ... }:

{
  systemd.services = {
    docker-published-ports-private = {
      description = "Restrict direct access to Atlas Docker application ports";
      wantedBy = [ "multi-user.target" ];
      requires = [ "docker.service" ];
      after = [ "docker.service" ];
      partOf = [ "docker.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu

        IPTABLES=${pkgs.iptables}/bin/iptables
        CHAIN="ATLAS-DOCKER-PRIVATE"
        CONTROL_PORTS="5553 8001 8019"
        # Technitium DNS: 53/tcp y 53/udp, accesible desde LAN y NetBird.
        # Technitium: DNS 53, consola HTTP 8665 y consola HTTPS 53443.
        PRIVATE_PORTS="53 1080 1231 1800 2283 2322 2450 3000 3004 3067 3131 3160 3232 3421 3422 3455 3456 3535 3552 3590 4533 4534 5000 7575 7644 8000 8090 8288 8555 8665 8888 9180 9191 9192 9920 9999 53443"

        $IPTABLES -w -N "$CHAIN" 2>/dev/null || true
        $IPTABLES -w -F "$CHAIN"

        # Docker-to-Docker traffic is required by Zoraxy and internal services.
        $IPTABLES -w -A "$CHAIN" -i br+ -j RETURN
        $IPTABLES -w -A "$CHAIN" -i docker0 -j RETURN

        # Never expose privileged control APIs on the host, even to the LAN.
        for port in $CONTROL_PORTS; do
          for protocol in tcp udp; do
            $IPTABLES -w -A "$CHAIN" -p "$protocol" -m conntrack --ctorigdstport "$port" -j DROP
          done
        done

        # Keep user-facing panels and app ports available only to trusted clients.
        $IPTABLES -w -A "$CHAIN" -i wt0 -j RETURN
        $IPTABLES -w -A "$CHAIN" -s 192.168.1.0/24 -j RETURN

        # Block direct WAN access to app UIs and proxy ports; Zoraxy's bridge
        # traffic was allowed above and public 80/443 are not in this list.
        for port in $PRIVATE_PORTS; do
          for protocol in tcp udp; do
            $IPTABLES -w -A "$CHAIN" -p "$protocol" -m conntrack --ctorigdstport "$port" -j DROP
          done
        done

        $IPTABLES -w -A "$CHAIN" -j RETURN
        $IPTABLES -w -C DOCKER-USER -j "$CHAIN" 2>/dev/null || \
          $IPTABLES -w -I DOCKER-USER 1 -j "$CHAIN"

        # Protect IPv6-published containers too, when Docker created its
        # DOCKER-USER chain. Global IPv6 clients are not on the trusted allowlist.
        IP6TABLES=${pkgs.iptables}/bin/ip6tables
        if $IP6TABLES -w -S DOCKER-USER >/dev/null 2>&1; then
          $IP6TABLES -w -N "$CHAIN" 2>/dev/null || true
          $IP6TABLES -w -F "$CHAIN"
          $IP6TABLES -w -A "$CHAIN" -i br+ -j RETURN
          $IP6TABLES -w -A "$CHAIN" -i docker0 -j RETURN
          for port in $CONTROL_PORTS; do
            for protocol in tcp udp; do
              $IP6TABLES -w -A "$CHAIN" -p "$protocol" -m conntrack --ctorigdstport "$port" -j DROP
            done
          done
          $IP6TABLES -w -A "$CHAIN" -i wt0 -j RETURN
          $IP6TABLES -w -A "$CHAIN" -s fc00::/7 -j RETURN
          for port in $PRIVATE_PORTS; do
            for protocol in tcp udp; do
              $IP6TABLES -w -A "$CHAIN" -p "$protocol" -m conntrack --ctorigdstport "$port" -j DROP
            done
          done
          $IP6TABLES -w -A "$CHAIN" -j RETURN
          $IP6TABLES -w -C DOCKER-USER -j "$CHAIN" 2>/dev/null || \
            $IP6TABLES -w -I DOCKER-USER 1 -j "$CHAIN"
        fi
      '';
    };
  };
}
