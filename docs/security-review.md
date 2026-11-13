# Revisión de firewall y privilegios

**Alcance:** revisión estática de la configuración NixOS de los cinco hosts.
No se ha inspeccionado el estado runtime de iptables/nftables, interfaces
activas, puertos escuchando ni publicación real de los Compose externos.
Los cambios de firewall retiran DNS/53 de la cadena INPUT de Atlas y añaden
políticas DOCKER-USER para los puertos publicados de Technitium en Atlas y Pico.
No se cambian los Compose ni sus mapeos de puertos. Los Compose no están
declarados en este repositorio; el modo bridge de Atlas sí se ha confirmado
mediante `docker inspect`, mientras que el estado runtime de Pico debe
comprobarse después de desplegar la generación.

## Atlas

### Firewall del host (INPUT)

El firewall del host permite actualmente:

- TCP: SSH 22, HTTP/HTTPS 80/443, Syncthing GUI 8384, puertos RustDesk
  21115–21119, Syncthing 22000, 8621 y Minecraft 25565.
- UDP: descubrimiento Syncthing 21027, Syncthing 22000, RustDesk 21116 y 8621.

Se retiraron TCP/UDP 53 de `networking.firewall.allowed*Ports`: Technitium
DNS se ejecuta como contenedor, no como servicio DNS nativo declarado en NixOS.
El puerto 53 continúa en `PRIVATE_PORTS` de DOCKER-USER: LAN
(`192.168.1.0/24`) y NetBird (`wt0`) conservan acceso, mientras que otros
orígenes quedan bloqueados por esta política.

Esta explicación del forwarding presupone que el Compose publica DNS mediante
una red bridge. Si Technitium usa `network_mode: host`, el tráfico llega a
INPUT y hay que revisar las aperturas TCP/UDP 53 antes de desplegar. El modo de
red y las publicaciones reales no están versionados en este flake.

No se han eliminado otros puertos porque el repositorio por sí solo no confirma
si cada uno se utiliza desde un servicio nativo o desde una aplicación externa
al flake. Comprueba las escuchas reales en Atlas antes de cualquier limpieza
adicional:

    sudo ss -lntup
    sudo iptables -vnL INPUT
    sudo ip6tables -vnL INPUT

### Puertos publicados por Docker

Los puertos publicados por Docker no deben confundirse con las excepciones
INPUT del firewall NixOS. La política de aplicaciones se instala en
`DOCKER-USER` mediante `modules/atlas-docker.nix`:

- Permite tráfico entre bridges Docker para la comunicación interna prevista.
- Mantiene acceso de la LAN IPv4 `192.168.1.0/24` y NetBird `wt0` a los
  paneles que el propietario necesita administrar.
- Bloquea desde otras redes los puertos publicados declarados en
  `PRIVATE_PORTS`.
- Bloquea las APIs de control 5553, 8001 y 8019 incluso desde LAN/NetBird,
  manteniendo la comunicación interna entre contenedores.
- Conserva Zoraxy 80/443, SSH, RustDesk, Syncthing y Minecraft fuera de la
  lista de bloqueo de aplicaciones.

Para IPv6, la regla permite bridges, NetBird y direcciones ULA `fc00::/7`.
Una LAN que use IPv6 global fuera de ULA no obtiene el mismo acceso directo a
los paneles; en ese caso usar IPv4 o NetBird, o definir conscientemente el
prefijo IPv6 confiable tras comprobarlo en el router.

Después de desplegar una generación, revisar contadores y funcionamiento:

    sudo iptables -vnL DOCKER-USER
    sudo iptables -vnL ATLAS-DOCKER-PRIVATE
    sudo ip6tables -vnL DOCKER-USER
    sudo ip6tables -vnL ATLAS-DOCKER-PRIVATE

Probar los paneles desde la LAN, desde NetBird y desde una red no confiable.
No asumir que un contador en cero demuestra una regla errónea: puede que no
haya llegado tráfico que la active.

## Escritorios: Elytra y Titan

El módulo compartido abre deliberadamente varios accesos asociados a las
funciones que el propietario utiliza:

- Stremio TCP 11470/12470 para Chromecast.
- Avahi/mDNS y sus reglas dinámicas para descubrimiento local.
- Sunshine y Steam Remote Play abren sus puertos mediante sus opciones
  `openFirewall`.
- Syncthing habilita sus puertos predeterminados.

No se han cambiado estas reglas a filtros por interfaz porque los archivos de
hardware no identifican de forma fiable el nombre de la interfaz LAN de cada
máquina y Elytra/Titan también utilizan NetBird y, en Elytra, Cloudflare WARP.
No conviene sustituir los accesos existentes por un nombre de interfaz
supuesto. La siguiente revisión puede limitar Stremio/Chromecast a la LAN
cuando se hayan recogido los nombres de interfaz y subredes reales de ambos
equipos.

SSH sigue permitido con contraseña, sin acceso directo de root y protegido
por Fail2ban. No se ha forzado autenticación solo con clave porque eso podría
interrumpir la administración remota antes de probar claves de recuperación
en ambos escritorios.

## Pico

Pico permite SSH TCP/22 en el firewall INPUT del host y confía en la interfaz
NetBird `wt0`. La unidad systemd `pico-technitium-docker-firewall` instala
la cadena `PICO-TECHNITIUM-PRIVATE` en `DOCKER-USER` para restringir
Technitium DNS cuando usa Docker bridge:

- Permite DNS 53/tcp y 53/udp y las consolas 8665/tcp y 53443/tcp desde
  `192.168.1.0/24` y NetBird (`wt0`).
- Bloquea esos puertos publicados desde otros orígenes.
- Conserva el tráfico entre bridges Docker para que los contenedores puedan
  comunicarse entre sí.
- Aplica la misma política a IPv6 si Docker crea la cadena IPv6
  `DOCKER-USER`; permite NetBird y direcciones ULA `fc00::/7`.

El Compose de Technitium no está versionado en este repositorio. La política
presupone publicación mediante bridge, como se ha verificado en Atlas. Si Pico
usa `network_mode: host`, `DOCKER-USER` no filtra ese tráfico y habrá que
revisar INPUT antes de aplicar la generación. Una LAN con IPv6 global fuera
de ULA necesitará añadir su prefijo real para mantener acceso IPv6 directo.

El Arcane Edge Agent abre una conexión saliente hacia el Manager de Atlas, no
necesita un puerto entrante de agente publicado.

El contenedor Agent monta `/var/run/docker.sock` sin modo de solo lectura.
Eso concede capacidad de administración muy elevada y es inherente a la
función de Arcane Edge. Mantén el token de agente fuera de Git y permite
administrar el entorno solo a cuentas de confianza.

## Privilegios Docker

Pertenecer al grupo Unix `docker` equivale en la práctica a poder obtener
privilegios de root a través del daemon. El grupo está asignado de forma
deliberada:

- En Elytra y Titan, para administración local de contenedores y Distrobox.
- En Atlas y Pico, para el flujo de administración del homelab.

No se elimina el grupo en esta revisión porque rompería el flujo de
administración existente y el acceso local a Docker. No añadas usuarios
adicionales al grupo sin considerar que pasan a ser administradores del host.
No expongas el socket Docker por TCP.

En Atlas, Arcane no accede directamente al socket del host: utiliza
`wollomatic/socket-proxy` a través de una red Docker privada, con el socket
montado en solo lectura y una allowlist de métodos/rutas. El proxy reduce la
superficie de API, pero Arcane sigue pudiendo ejecutar acciones de alto impacto
como crear contenedores y lanzar procesos. Restringe el panel de Arcane a
personas de plena confianza.

## Modularización realizada

El bloque específico de Docker de Atlas se ha extraído de
`hosts/servidor/configuration.nix` a `modules/atlas-docker.nix`:

- Motor Docker y política `DOCKER-USER`.
- Proxy de socket, Arcane Manager y PostgreSQL.
- Red privada Arcane y dependencias systemd para el inicio ordenado.

El archivo de Atlas queda centrado en hardware, kernel, firewall INPUT,
almacenamiento, rendimiento y configuración específica del equipo. El módulo
de Docker solo se importa desde Atlas. Pico mantiene su política Technitium
declarada directamente en `hosts/zimablade/configuration.nix`; ambas reglas
son independientes y específicas de cada servidor.

## Comprobaciones pendientes en hardware

1. Capturar `ss -lntup` en Atlas y confirmar los puertos nativos que realmente
   escuchan.
2. Verificar Technitium DNS en Atlas y Pico desde LAN/NetBird. Confirmar que
   ambos contenedores usan bridge y publican 53/tcp+udp, 8665/tcp y
   53443/tcp. Revisar las cadenas `ATLAS-DOCKER-PRIVATE` y
   `PICO-TECHNITIUM-PRIVATE`, y comprobar que el router no publique esos
   puertos hacia redes no confiables. Si un contenedor usa `network_mode: host`,
   revisar INPUT porque DOCKER-USER no se aplica.
3. Validar los paneles de Atlas desde LAN, NetBird y una red no confiable.
4. En Elytra y Titan, recoger `ip -br link`, `ip route` e IP/subred LAN para
   estudiar reglas por interfaz sin cortar Chromecast, Sunshine, Steam,
   Syncthing, NetBird o WARP.
5. Revisar miembros del grupo `docker` y mantener el conjunto mínimo.

Estos cambios no se despliegan automáticamente. La evaluación NixOS confirma
que la configuración puede evaluarse, pero no sustituye las pruebas de
conectividad con los servicios reales.
