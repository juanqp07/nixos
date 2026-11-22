# Endurecimiento Docker y CrowdSec: Atlas, Pico y Titan

**Revisión:** 21 de noviembre de 2026
**Alcance:** configuración declarativa de Arcane en Atlas y su agente remoto en Pico, además del endurecimiento Docker y las comprobaciones del stack CrowdSec/Zoraxy en Atlas. Esta documentación no implica que las generaciones NixOS se hayan desplegado en los hosts.

## Resumen por equipo

| Equipo | Estado | Cambios de esta rama |
|---|---|---|
| Atlas | CrowdSec/Zoraxy ya adquiere y parsea logs; bouncer consulta LAPI. Reglas de red pendientes de desplegar. | Socket proxy Wollomatic con allowlist por método/ruta para Arcane y política DOCKER-USER para puertos publicados, incluidos DNS y consolas Technitium. |
| Pico (ZimaBlade) | NetBird, Fail2ban, rotación de logs y poda Docker. | Arcane Agent v3.0.1 con conexión saliente al Manager de Atlas por TCP/3552 y sin puerto de escucha/publicación 3553; política DOCKER-USER para Technitium. |
| Titan | Ya está en el flake como host NixOS. La SSD de juegos y Avahi se corrigieron en PR #18. | No se cambian kernel, AMDGPU, scheduler ni ajustes de overdrive sin pruebas físicas. |

Los paneles de administración de Atlas y Pico no están redirigidos desde el router a Internet, según la información del propietario. Las reglas DOCKER-USER son defensa en profundidad ante una publicación accidental de puertos, no una afirmación de que esos paneles estuvieran expuestos públicamente.

## Technitium DNS en Atlas y Pico

Technitium DNS se ejecuta en contenedores Docker en ambos servidores. El
Compose no está versionado en este flake, así que los mapeos deben comprobarse
en los hosts y no se modifican desde Nix.

Los mapeos observados en Atlas y compartidos para ambos servidores son:

| Puerto del host | Destino del contenedor | Protocolo | Función |
|---|---|---|---|
| 53 | 53 | TCP/UDP | Resolución DNS |
| 8665 | 5380 | TCP | Consola web HTTP |
| 53443 | 53443 | TCP | Consola web HTTPS |

Los puertos 853, 443, 80, 8053 y 67 aparecen como expuestos por la imagen,
pero no como puertos publicados en la salida de Docker compartida. No se
abren ni se alteran aquí.

- **Atlas:** `ATLAS-DOCKER-PRIVATE` filtra los tres puertos publicados
  (53/tcp+udp, 8665/tcp y 53443/tcp) en `DOCKER-USER`. LAN
  (`192.168.1.0/24`) y NetBird (`wt0`) mantienen acceso. Los demás orígenes
  quedan bloqueados. La regla IPv6 permite NetBird y direcciones ULA
  (`fc00::/7`).
- **Pico:** la unidad systemd `pico-technitium-docker-firewall` instala
  `PICO-TECHNITIUM-PRIVATE` en `DOCKER-USER` y aplica la misma política:
  LAN/NetBird permitidos, otros orígenes bloqueados y comunicación entre
  bridges Docker conservada. La política IPv6 se aplica si Docker crea
  `DOCKER-USER` para IPv6 y permite NetBird y ULA (`fc00::/7`).

Las políticas presuponen Docker bridge. En ese modo el tráfico publicado
atraviesa el forwarding de Docker y no la cadena INPUT de NixOS. Si un
Compose cambia a `network_mode: host`, `DOCKER-USER` deja de filtrar ese
tráfico y será necesario revisar INPUT. Una LAN que use IPv6 global fuera de
ULA debe añadir su prefijo real a la lista de orígenes confiables si necesita
acceso DNS/consola por IPv6 directo.

Tras desplegar, comprobar en ambos hosts el `NetworkMode` y los
`PortBindings` del contenedor, revisar los contadores de las cadenas y probar
DNS y las consolas desde LAN, NetBird y una red no confiable. Las reglas de
firewall no sustituyen la política de recursión/ACL configurada dentro de
Technitium ni las reglas del router.

## Atlas

### Arcane y Docker socket

Arcane accede al Docker Engine de Atlas a través de `wollomatic/socket-proxy:1.13.2`, en la red privada `arcane-net`. Arcane utiliza `DOCKER_HOST=tcp://arcane-docker-proxy:2375`, usando el nombre DNS del propio contenedor administrado por `oci-containers` en lugar de un alias adicional; el proxy monta el socket del host en solo lectura y aplica una allowlist por método HTTP y ruta.

El proxy no publica puertos en el host ni está conectado a `staticnet` o `warpnet`. Solo acepta clientes identificados como `arcane` y `arcane-upgrader`; no se permite un rango de subred completo. El contenedor se ejecuta con filesystem de solo lectura, sin capabilities, con `no-new-privileges`, límite de memoria de 64 MiB y límite de procesos.

Antes de iniciar Arcane, la unidad `arcane-proxy-ready` ejecuta `docker exec arcane-docker-proxy ./healthcheck` hasta que el binario incluido por Wollomatic confirma que puede acceder al socket. Se invoca directamente en formato exec, sin shell. No se configura `--health-cmd` desde Docker CLI: ese parámetro genera una prueba `CMD-SHELL`, incompatible con la imagen mínima de Wollomatic, que no incluye `/bin/sh`. Si el proxy no responde dentro de 180 segundos, systemd muestra los últimos logs y bloquea el arranque de Arcane.

La allowlist sigue la integración oficial de Arcane e incluye las rutas necesarias para consultar contenedores, eventos, imágenes, redes, volúmenes, builds, registros y operaciones de gestión. Se mantienen bloqueados los métodos y endpoints que no están expresamente declarados. No se debe sustituir por `allowGET=.*`, `allowPOST=.*` ni publicar el puerto 2375 fuera de la red privada.

El Manager de Atlas tampoco usa `--health-cmd`: Docker CLI lo serializa como
`CMD-SHELL`, pero la imagen no incluye `/bin/sh`. La configuración desactiva
ese healthcheck Docker y programa `arcane-healthcheck.timer`, que ejecuta el
binario `./arcane health` directamente dentro del contenedor mediante
`docker exec`. Esto mantiene la comprobación real sin añadir una shell a la
imagen ni relajar su aislamiento.

El helper temporal de actualización de Arcane requiere el alias `arcane-upgrader` en `-allowfrom`. La versión actual de Arcane debe crear ese alias; tras cambiar una instalación antigua, recrear el contenedor Arcane una vez para que las futuras autoactualizaciones puedan conectar.

La red `arcane-net` se conserva para Arcane, el proxy y PostgreSQL. El montaje directo del socket en Zoraxy es independiente y no se modifica.

**Límite de seguridad:** el proxy reduce la superficie de API disponible, pero Arcane sigue necesitando operaciones de alto impacto (por ejemplo, crear contenedores, ejecutar procesos y eliminar recursos). Solo usuarios de plena confianza deben administrar Arcane y su panel debe permanecer restringido a LAN/NetBird.

### Acceso a puertos publicados por Docker

Docker puede publicar puertos a través de sus reglas de forwarding sin pasar por la cadena INPUT normal de NixOS. La política de esta rama se instala en `DOCKER-USER`:

- Permite los bridges Docker para el tráfico interno previsto por la arquitectura.
- Mantiene el acceso de la LAN `192.168.1.0/24` y de NetBird (`wt0`) a paneles/servicios que deben seguir siendo administrables.
- Bloquea desde otras redes los puertos de aplicaciones y paneles indicados en `hosts/servidor/configuration.nix`.
- Mantiene las APIs de control configuradas en `CONTROL_PORTS` fuera del acceso directo desde host/LAN/NetBird; los contenedores de los bridges siguen pudiendo comunicarse con ellas.
- No modifica los puertos públicos del proxy (80/443), SSH ni los servicios que el propietario decidió mantener accesibles.

La regla IPv6 permite NetBird y direcciones ULA (`fc00::/7`), pero no una LAN que use direcciones IPv6 globales. Los clientes de esa LAN deberán utilizar IPv4 o NetBird para acceder directamente a esos paneles, salvo que se amplíe la allowlist IPv6 tras confirmar el prefijo LAN real.

La lista de puertos y las redes de confianza deben revisarse contra el estado real de Atlas antes de desplegar. No se ha aplicado esta política al host todavía.

### CrowdSec + Zoraxy: configuración que ya está probada

Zoraxy tiene `ENABLELOG=true`. Su directorio de trabajo es `/opt/zoraxy/config`, por lo que los logs se guardan en `/opt/zoraxy/config/log/`, no en `/opt/zoraxy/log/`.

Montajes correctos:

- En Zoraxy, `/mnt/datos/AppData/zoraxy/config/ -> /opt/zoraxy/config/`.
- En CrowdSec, `/mnt/datos/AppData/zoraxy/config/log/ -> /opt/zoraxy/config/log/` en solo lectura.

El archivo `/etc/crowdsec/acquis.d/zoraxy.yaml` debe incluir el campo obligatorio `source`:

```yaml
source: file
filenames:
  - /opt/zoraxy/config/log/zr_*.log
labels:
  type: zoraxy
```

La colección ya configurada es `Raithmir/zoraxy`. El bouncer consulta el LAPI por la red Docker compartida con `http://crowdsec:8080`; no necesita publicar el puerto 8080 del contenedor en el host.

El puerto `8019:8080` está comentado/eliminado en el Compose actual. Debe permanecer sin publicar.

#### Verificación observada el 2 de noviembre de 2026

Después de corregir la ruta y añadir `source: file`, los resultados compartidos por el propietario fueron:

- CrowdSec añadió los archivos `zr_2026-1.log` a `zr_2026-11.log` como fuentes y comenzó a seguirlos desde el final.
- Métricas posteriores: 8 líneas leídas, 8 parseadas, 0 sin parsear, 3 enviadas a escenarios y 3 excluidas por whitelist.
- El parser `Raithmir/zoraxy-logs` registró líneas parseadas.
- El bouncer consultó repetidamente `/v1/decisions/stream` y recibió HTTP 200.
- `cscli alerts list` devolvió `No active alerts`.

Las líneas en whitelist no representan fallos: la lista excluye las direcciones privadas. Que haya líneas enviadas a escenarios no significa que se haya generado una alerta. Las decisiones que aparecen con origen CAPI son decisiones recibidas de CrowdSec Central API, no detecciones locales.

**Pendiente de verificar en la interfaz de Zoraxy:** el plugin `com.anthonyrubick.zoraxycrowdsecbouncer` debe estar en el mismo Dynamic Capture Plugin Group/tag que cada host que se quiera proteger. Que el bouncer reciba decisiones y consulte el stream no prueba por sí solo que todos los hosts estén asociados ni que el bloqueo HTTP 403 se haya ejercitado.

## Pico (ZimaBlade)

### Arcane Agent v3

La configuración de esta rama declara Arcane Manager v3.1.1 en Atlas
(`modules/atlas-docker.nix`) y Arcane Agent v3.0.1 en Pico
(`hosts/zimablade/configuration.nix`). Ambos siguen fijados por tag y digest;
NixOS controla sus imágenes y evita que las actualice por su cuenta un updater
interno. El Agent de Pico no se actualiza en este cambio: primero se debe revisar
su estado runtime y después usar el flujo documentado en `docs/arcane-updates.md`.

Pico utiliza `ARCANE_AGENT=true`, `ARCANE_AGENT_TRANSPORT=auto` y
`ARCANE_MANAGER_API_URL=http://192.168.1.143:3552`. El agente inicia la
conexión hacia el Manager de Atlas por TCP/3552. **No escucha en TCP/3553 ni
publica ese puerto**: no debe añadirse una apertura de 3553 al firewall INPUT
ni una regla para ese puerto en la cadena `DOCKER-USER` de Pico.

El Manager publica TCP/3552 en Atlas. La política `ATLAS-DOCKER-PRIVATE`
permite el acceso desde la LAN `192.168.1.0/24` y NetBird (`wt0`) antes
de bloquear otros orígenes. La unidad `pico-technitium-docker-firewall`
sigue dedicada a los puertos publicados de Technitium: DNS 53/tcp+udp y
consolas 8665/tcp y 53443/tcp.

El token de inscripción se mantiene fuera del repositorio en
`/var/lib/arcane-agent/agent.env` con la variable
`ARCANE_AGENT_TOKEN=...`. No reutilices el antiguo `AGENT_TOKEN` del modo
Direct ni copies el valor del token a Git, documentación o registros. El
volumen Docker `arcane-agent-data` conserva el estado y la clave persistente
del agente; no lo borres al actualizar o reinscribir Pico.

El agente monta `/var/run/docker.sock` para administrar el motor local de
Pico. Este acceso tiene privilegios equivalentes a la administración del host:
el token y el acceso al Manager deben reservarse a cuentas de plena confianza.
No expongas el socket Docker por TCP.

#### Reinscripción y validación

La migración de v2 a v3 puede dejar los agentes Direct antiguos en estado
Pending. Para reinscribir Pico, genera un token nuevo desde **Agents →
Connection & Agent → Generate Enrollment Token** en el Manager de Atlas y
sustituye el valor de `ARCANE_AGENT_TOKEN` en el archivo privado de Pico.
Los pasos completos y las comprobaciones están en
[`docs/arcane-v3-pico.md`](arcane-v3-pico.md).

Tras desplegar la generación, comprueba el contenedor y sus logs en Pico y
confirma que el entorno aparece Online en Arcane de Atlas. Verifica también
que conserva `/var/lib/dockge/stacks` como Projects Directory y que los
proyectos existentes siguen disponibles. No hace falta publicar TCP/3553
para esta arquitectura v3.

## Titan

Titan está declarado en `flake.nix` como `titan = mkHost ... "torre"`. El PR #18, ya integrado en `main` el 2 de noviembre de 2026, actualizó Avahi y dejó declarada la SSD ext4 de 1 TB en `/mnt/juegos`, junto con los directorios Steam/Heroic/Downloads/Data con propietario `juan:users` y permisos `0775`.

La evaluación de NixOS en GitHub Actions para el commit resultante de `main` terminó correctamente. Esto verifica la evaluación de los cinco hosts, no la salud física de GPU, SSD, temperaturas ni rendimiento de juegos.

No se han añadido ajustes especulativos a Titan: se conservan `amd_pstate=active`, AMDGPU, OpenCL, LACT y los parámetros actuales de gaming. Cualquier cambio de kernel, scheduler, overdrive o `HSA_OVERRIDE_GFX_VERSION` debe validarse con pruebas en el equipo real y con las aplicaciones que utilicen ROCm.

## Despliegue y validación pendientes

Esta rama es una propuesta de configuración; no ejecuta cambios remotos en los hosts.

### Atlas

1. Confirmar que la LAN sigue siendo `192.168.1.0/24` y que NetBird usa `wt0`.
2. Construir y revisar la generación antes de activar:
   `sudo nixos-rebuild build --flake .#atlas`.
3. Tras desplegar en una ventana de mantenimiento, comprobar `sudo iptables -vnL DOCKER-USER` y, si procede, `sudo ip6tables -vnL DOCKER-USER`.
4. Verificar que `arcane-docker-proxy` está `healthy`, que Arcane conecta a `arcane-docker-proxy:2375` y probar listado, logs, inicio/parada, stacks, imágenes y builds.
5. Asociar el plugin CrowdSec a los tags Dynamic Capture necesarios y comprobar las métricas por hostname.

### Pico

1. Crear el entorno Edge llamado pico en Arcane de Atlas y guardar el token fuera de Git en /var/lib/arcane-agent/agent.env.
2. Construir y revisar sudo nixos-rebuild build --flake .#pico.
3. Tras desplegar, comprobar que el contenedor arcane-agent está activo y aparece Online en Arcane de Atlas.
4. Configurar /var/lib/dockge/stacks como Projects Directory del entorno Pico y validar los proyectos existentes.

### Titan

La configuración del SSD y Avahi ya está en `main`. Tras aplicar la generación en Titan, verificar `findmnt /mnt/juegos`, permisos de escritura con el usuario `juan`, `vainfo`/Vulkan y temperaturas bajo una carga de juego real.

