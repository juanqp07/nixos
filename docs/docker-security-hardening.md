# Endurecimiento Docker y CrowdSec: Atlas, Pico y Titan

**Revisión:** 6 de noviembre de 2026
**Alcance:** cambios declarativos en NixOS y comprobaciones del stack CrowdSec/Zoraxy en Atlas. Esta documentación no implica que se hayan desplegado las generaciones NixOS en Atlas o Pico.

## Resumen por equipo

| Equipo | Estado | Cambios de esta rama |
|---|---|---|
| Atlas | CrowdSec/Zoraxy ya adquiere y parsea logs; bouncer consulta LAPI. Reglas de red pendientes de desplegar. | Socket proxy Wollomatic con allowlist por método/ruta para Arcane y política DOCKER-USER para puertos publicados. |
| Pico (ZimaBlade) | Ya tiene NetBird, Fail2ban, rotación de logs y poda Docker. | Restringir el puerto publicado de Dockge (5001) a LAN/NetBird. |
| Titan | Ya está en el flake como host NixOS. La SSD de juegos y Avahi se corrigieron en PR #18. | No se cambian kernel, AMDGPU, scheduler ni ajustes de overdrive sin pruebas físicas. |

Los paneles de administración de Atlas y Pico no están redirigidos desde el router a Internet, según la información del propietario. Las reglas DOCKER-USER son defensa en profundidad ante una publicación accidental de puertos, no una afirmación de que esos paneles estuvieran expuestos públicamente.

## Atlas

### Arcane y Docker socket

Arcane accede al Docker Engine de Atlas a través de `wollomatic/socket-proxy:1.13.2`, en la red privada `arcane-net`. Arcane utiliza `DOCKER_HOST=tcp://arcane-docker-proxy:2375`, usando el nombre DNS del propio contenedor administrado por `oci-containers` en lugar de un alias adicional; el proxy monta el socket del host en solo lectura y aplica una allowlist por método HTTP y ruta.

El proxy no publica puertos en el host ni está conectado a `staticnet` o `warpnet`. Solo acepta clientes identificados como `arcane` y `arcane-upgrader`; no se permite un rango de subred completo. El contenedor se ejecuta con filesystem de solo lectura, sin capabilities, con `no-new-privileges`, límite de memoria de 64 MiB y límite de procesos.

Antes de iniciar Arcane, la unidad `arcane-proxy-ready` ejecuta `docker exec arcane-docker-proxy ./healthcheck` hasta que el binario incluido por Wollomatic confirma que puede acceder al socket. Se invoca directamente en formato exec, sin shell. No se configura `--health-cmd` desde Docker CLI: ese parámetro genera una prueba `CMD-SHELL`, incompatible con la imagen mínima de Wollomatic, que no incluye `/bin/sh`. Si el proxy no responde dentro de 180 segundos, systemd muestra los últimos logs y bloquea el arranque de Arcane.

La allowlist sigue la integración oficial de Arcane e incluye las rutas necesarias para consultar contenedores, eventos, imágenes, redes, volúmenes, builds, registros y operaciones de gestión. Se mantienen bloqueados los métodos y endpoints que no están expresamente declarados. No se debe sustituir por `allowGET=.*`, `allowPOST=.*` ni publicar el puerto 2375 fuera de la red privada.

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

Pico es el host `pico` de `hosts/zimablade` (Celeron N3450 / Apollo Lake); no es la Raspberry Pi, que en el flake se llama `palco`.

La configuración ya mantiene SSH sin acceso root, Fail2ban, NetBird, límites de journald, poda semanal de Docker y microcódigo Intel disponible. Dockge requiere el socket Docker para administrar stacks y contenedores; este cambio no modifica ese requisito ni publica el servicio en una nueva interfaz.

El único puerto de administración publicado por el Compose declarativo de Pico es TCP/5001. La regla de `DOCKER-USER` de esta rama permite nuevas conexiones a ese puerto desde:

- La LAN IPv4 `192.168.1.0/24`.
- NetBird por `wt0`.
- Para IPv6, NetBird y direcciones ULA `fc00::/7`.

Las conexiones nuevas desde otros orígenes se descartan. Las respuestas de conexiones ya establecidas se permiten para no romper sesiones existentes durante una activación. Si la LAN usa IPv6 global, el panel debe abrirse por IPv4 o NetBird, o se deberá añadir el prefijo IPv6 LAN real a la política.

La regla se activa después de Docker y se vuelve a aplicar cuando Docker se reinicia. No se ha desplegado todavía en Pico.

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

1. Confirmar que la LAN del host está en `192.168.1.0/24` y que `wt0` está activo.
2. Construir y revisar `sudo nixos-rebuild build --flake .#pico`.
3. Tras desplegar, comprobar `sudo iptables -vnL DOCKER-USER` y probar Dockge desde un equipo LAN y desde NetBird.
4. Confirmar que TCP/5001 no responde desde una red no autorizada.

### Titan

La configuración del SSD y Avahi ya está en `main`. Tras aplicar la generación en Titan, verificar `findmnt /mnt/juegos`, permisos de escritura con el usuario `juan`, `vainfo`/Vulkan y temperaturas bajo una carga de juego real.

