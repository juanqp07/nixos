# Endurecimiento Docker y CrowdSec: Atlas, Pico y Titan

**Revisión:** 10 de noviembre de 2026
**Alcance:** configuración declarativa de Arcane en Atlas y su agente remoto en Pico, además del endurecimiento Docker y las comprobaciones del stack CrowdSec/Zoraxy en Atlas. Esta documentación no implica que las generaciones NixOS se hayan desplegado en los hosts.

## Resumen por equipo

| Equipo | Estado | Cambios de esta rama |
|---|---|---|
| Atlas | CrowdSec/Zoraxy ya adquiere y parsea logs; bouncer consulta LAPI. Reglas de red pendientes de desplegar. | Socket proxy Wollomatic con allowlist por método/ruta para Arcane y política DOCKER-USER para puertos publicados. |
| Pico (ZimaBlade) | NetBird, Fail2ban, rotación de logs y poda Docker. | Arcane Edge Agent conectado al Manager de Atlas; sin panel adicional ni puertos entrantes publicados. |
| Titan | Ya está en el flake como host NixOS. La SSD de juegos y Avahi se corrigieron en PR #18. | No se cambian kernel, AMDGPU, scheduler ni ajustes de overdrive sin pruebas físicas. |

Los paneles de administración de Atlas y Pico no están redirigidos desde el router a Internet, según la información del propietario. Las reglas DOCKER-USER son defensa en profundidad ante una publicación accidental de puertos, no una afirmación de que esos paneles estuvieran expuestos públicamente.

## Technitium DNS en Atlas y Pico

Technitium DNS es el servicio DNS utilizado actualmente en ambos servidores y
se ejecuta en contenedores Docker. Sus Compose no están declarados en el flake,
por lo que este repositorio no fija el modo de red ni los mapeos efectivos de
puertos. No se deben deducir las publicaciones reales únicamente a partir del
firewall INPUT de NixOS.

- **Atlas:** el puerto DNS 53/tcp y 53/udp figura en `PRIVATE_PORTS` de
  `ATLAS-DOCKER-PRIVATE`. La cadena permite primero LAN
  (`192.168.1.0/24`) y NetBird (`wt0`), y bloquea después esos puertos para
  otros orígenes. El puerto 53 no se abre en INPUT porque el caso previsto es
  publicación mediante Docker bridge. Si el Compose cambia a
  `network_mode: host`, hay que revisar INPUT.
- **Pico:** el firewall INPUT de NixOS solo abre SSH TCP/22. Si Technitium
  publica 53/tcp y 53/udp mediante bridge, el tráfico utiliza el forwarding de
  Docker y no esas reglas INPUT. El flake no declara una cadena
  `DOCKER-USER` específica para DNS en Pico, así que hay que verificar las
  publicaciones del Compose y las reglas del router para conocer la exposición
  efectiva. Si utiliza `network_mode: host`, el tráfico sí queda sujeto a
  INPUT y habría que revisar las aperturas del host.

Antes de cambiar puertos, redes o el firewall, comprobar en ambos hosts el
`network_mode` real del contenedor, sus publicaciones y el acceso DNS desde
LAN/NetBird y desde una red externa no confiable. Esta documentación no cambia
ni despliega los Compose.

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

### Arcane Edge Agent

Pico no ejecuta una segunda instancia de Arcane Manager ni otra base de datos. El único Manager y PostgreSQL permanecen en Atlas; Pico ejecuta únicamente el agente oficial de Arcane (ghcr.io/getarcaneapp/agent:v2.17.3) para que ambos Docker Engine se administren desde el mismo panel.

- El agente trabaja en modo Edge con EDGE_AGENT=true y EDGE_TRANSPORT=auto. Inicia una conexión saliente continua hacia http://192.168.1.143:3552 (Arcane Manager en Atlas, puerto TCP/3552).
- No se publica ningún puerto en Pico: no se necesita abrir TCP/3553 ni añadir reglas de entrada en NixOS o DOCKER-USER.
- El agente necesita acceso al Docker Engine local mediante /var/run/docker.sock; por tanto, el token de este entorno debe tratarse como una credencial administrativa de Pico.
- El token generado en Arcane se guarda exclusivamente en /var/lib/arcane-agent/agent.env como AGENT_TOKEN=.... El archivo no debe añadirse a Git ni copiarse a documentación o registros.
- La carpeta de proyectos que Dockge utilizaba, /var/lib/dockge/stacks, se conserva y se monta en el agente con la misma ruta absoluta. En Arcane, dentro del entorno Pico, configura **Storage & Limits → Projects Directory** como /var/lib/dockge/stacks. Así se podrán descubrir y administrar los Compose existentes sin moverlos ni cambiar las rutas relativas de sus bind mounts.
- El agente mantiene sus datos en el volumen Docker persistente arcane-agent-data.

#### Alta y despliegue del agente

1. En el Manager de Atlas, abre **Environments → Add Environment → Edge**, crea el entorno llamado pico y genera su configuración.
2. En Pico, crea el archivo de secreto antes de activar la generación NixOS:

       sudo install -d -m 0700 -o juan -g users /var/lib/arcane-agent
       sudo install -m 0600 -o juan -g users /dev/null /var/lib/arcane-agent/agent.env
       sudoedit /var/lib/arcane-agent/agent.env

   El contenido debe ser únicamente la variable y el token proporcionado por Arcane:

       AGENT_TOKEN=arc_...

3. Construye y revisa sudo nixos-rebuild build --flake .#pico; después aplica sudo nixos-rebuild switch --flake .#pico.
4. Comprueba docker logs arcane-agent y que Pico aparezca Online en el selector de entornos de Atlas.
5. En los ajustes de almacenamiento del entorno remoto, configura /var/lib/dockge/stacks como Projects Directory y comprueba que los Compose existentes aparecen antes de eliminar manualmente cualquier dato antiguo.

Si cambia la IP LAN de Atlas, actualiza MANAGER_API_URL en hosts/zimablade/configuration.nix y despliega la nueva generación. El agente usa el transporte Edge auto para mantener el canal iniciado desde Pico; no requiere conexiones entrantes desde Atlas.

El cambio elimina el contenedor Dockge, su directorio de datos de interfaz y la antigua regla DOCKER-USER que protegía TCP/5001. **No elimina /var/lib/dockge/stacks ni los archivos Compose**. Si el contenedor Dockge antiguo permanece tras cambiar de generación, verifica primero que Arcane Agent esté Online y que los proyectos se hayan detectado; después se puede retirar con sudo docker rm -f dockge.

La regla PICO-DOCKGE-PRIVATE puede seguir cargada en el kernel durante la sesión en que se retira la unidad antigua (la unidad original no tenía una acción ExecStop para limpiar iptables). Después de confirmar que Dockge ya no está ejecutándose, elimina esa regla residual una sola vez:

       for tool in iptables ip6tables; do
         sudo "$tool" -D DOCKER-USER -j PICO-DOCKGE-PRIVATE 2>/dev/null || true
         sudo "$tool" -F PICO-DOCKGE-PRIVATE 2>/dev/null || true
         sudo "$tool" -X PICO-DOCKGE-PRIVATE 2>/dev/null || true
       done

Esto no afecta a otros filtros de Docker: elimina únicamente la cadena creada para el antiguo puerto 5001 de Dockge.

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

