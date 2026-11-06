# Endurecimiento de red y acceso Docker en Atlas

Este documento describe el endurecimiento de red y acceso Docker de Atlas declarado en NixOS. Los cambios deben desplegarse en el servidor mediante una generación nueva.

## Qué cambia en Atlas

- Arcane utiliza `wollomatic/socket-proxy:1.13.2`, con socket del host montado en solo lectura, allowlist por método/ruta y clientes `arcane`/`arcane-upgrader`. El proxy no publica el puerto 2375 ni se conecta a redes externas.
- Se bloquea el acceso directo a los puertos publicados de aplicaciones y paneles desde redes no confiables. Los paneles siguen accesibles desde la LAN `192.168.1.0/24` y NetBird (`wt0`); los bridges Docker conservan el acceso de Zoraxy y las comunicaciones internas.
- Las APIs administrativas de IPFS RPC (5553), CrowdSec LAPI (8019) y Gluetun Control (8001) quedan protegidas frente al acceso directo desde el host/LAN/NetBird según las reglas declaradas.
- La restricción se instala en `DOCKER-USER`, ya que los puertos publicados por Docker pueden saltarse las reglas normales de INPUT de NixOS.
- No se filtran los puertos públicos de Zoraxy (80/443), SSH (22), RustDesk, Syncthing ni Minecraft (25565).

La lista protegida incluye DNS/AdGuard (53), IPFS RPC (5553), Gluetun API/proxies (8001, 1800, 8888), Zoraxy Admin (8000), Arcane (3552), paneles de administración y puertos HTTP directos de aplicaciones. El filtro es una barrera adicional para los puertos directos; no sustituye la autenticación ni las reglas del router.

La regla IPv6 permite NetBird, bridges Docker y direcciones ULA (`fc00::/7`). Los clientes LAN que solo tengan IPv6 global deberán entrar por IPv4 o NetBird para acceder directamente a los paneles.

## CrowdSec + Zoraxy: estado resuelto

La integración CrowdSec–Zoraxy ya se ha configurado y validado en el entorno. Esta PR no debe tratarla como una incidencia pendiente ni proponer volver a configurar el bouncer, la adquisición de logs, las etiquetas del plugin o sus credenciales.

La única recomendación de hardening relacionada que permanece aquí es mantener la LAPI de CrowdSec sin publicación innecesaria en el host. Si se elimina el mapeo Compose `8019:8080`, confirmar que el bouncer y CrowdSec comparten una red Docker y que el bouncer usa la dirección interna correspondiente (por ejemplo, `http://crowdsec:8080`). Esto es una modificación de exposición de red, no una reparación de la integración ya operativa.

No se deben modificar ni volver a desplegar los ajustes existentes de Zoraxy/CrowdSec como parte de esta PR sin una necesidad comprobada.

## Verificación después de aplicar

En Atlas, revisar las reglas Docker:

```bash
sudo iptables -vnL DOCKER-USER
sudo ip6tables -vnL DOCKER-USER
```

Comprobar que los paneles siguen accesibles desde LAN y NetBird, que los puertos directos protegidos no son accesibles desde redes no confiables y que Zoraxy continúa encaminando los servicios publicados por 80/443.

La unidad `arcane-proxy-ready` ejecuta directamente `docker exec arcane-docker-proxy ./healthcheck` y espera hasta 180 segundos a que el binario incluido por Wollomatic confirme el acceso al socket. No se usa `--health-cmd` de Docker CLI porque crea una prueba `CMD-SHELL`, incompatible con la imagen sin shell. Si falla, Arcane no arranca y se registran los últimos logs del proxy. Después, la validación funcional debe comprobar que Arcane puede consultar contenedores y logs, iniciar/parar contenedores y gestionar stacks, imágenes y builds. Un error HTTP 403 indica una ruta no incluida en la allowlist; un error de DNS/conexión apunta a red, alias o disponibilidad del proxy. No se debe resolver ninguno de estos errores abriendo todos los endpoints.

## Referencias

- [Docker: DOCKER-USER chain](https://docs.docker.com/engine/network/firewall-iptables/)
