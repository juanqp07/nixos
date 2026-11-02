# Endurecimiento de red y CrowdSec en Atlas

Este documento acompaña los cambios NixOS de la rama `security/atlas-docker-hardening`.
La configuración queda declarada, pero no se aplica al servidor hasta desplegar la generación nueva.

## Qué cambia en Atlas

- Arcane deja de montar `/var/run/docker.sock` directamente. Usa `wollomatic/socket-proxy` con el socket montado en solo lectura, sin capabilities y con allowlist de operaciones Docker.
- Se bloquea el acceso externo directo a los puertos publicados de aplicaciones, paneles y APIs que deben entrar por Zoraxy. Se mantienen accesibles desde la LAN `192.168.1.0/24`, NetBird (`wt0`) y los bridges Docker (para el tráfico del proxy y las comunicaciones entre contenedores).
- La restricción se instala en `DOCKER-USER`, ya que los puertos publicados por Docker pueden saltarse las reglas normales de INPUT de NixOS.
- No se filtran los puertos públicos de Zoraxy (80/443), SSH (22), RustDesk, Syncthing ni Minecraft (25565).

La lista protegida incluye DNS/AdGuard (53), IPFS RPC (5553), CrowdSec LAPI (8019), Gluetun API/proxies (8001, 1800, 8888), Zoraxy Admin (8000), Arcane (3552), paneles de administración y puertos HTTP directos de aplicaciones. Los paneles siguen accesibles desde la LAN/NetBird; desde Internet se deben usar los dominios servidos por Zoraxy.

La regla IPv6 permite NetBird, bridges Docker y direcciones ULA (`fc00::/7`). Los clientes LAN que solo tengan IPv6 global deberán entrar por IPv4 o NetBird para acceder directamente a los paneles.

## CrowdSec + Zoraxy: corregir la adquisición

### 1. Diagnóstico confirmado

CrowdSec ya tiene registrado el bouncer `zoraxy-crowdsec-bouncer`. Los registros del 29/10/2026 muestran consultas `GET /v1/decisions/stream` con HTTP 200 cada 10 segundos. Por tanto, la comunicación bouncer → LAPI ya funciona.

El problema observado es distinto: CrowdSec informa de que no encuentra archivos para:

```text
/opt/zoraxy/log/zr_*.log
```

Ese path existe (o se espera que exista) dentro de Zoraxy, pero no está montado en el contenedor CrowdSec. Sin logs y parser, CrowdSec no genera decisiones nuevas a partir del tráfico de Zoraxy.

### 2. Averiguar la ruta persistente real de los logs

En Atlas, ejecutar:

```bash
docker exec zoraxy sh -lc 'find /opt/zoraxy -type f -name "zr_*.log" 2>/dev/null'
docker inspect zoraxy --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
```

Identificar el directorio del host que contiene los archivos `zr_*.log`. No crear una ruta vacía: debe ser el directorio real donde Zoraxy está escribiendo los logs.

En el proyecto Compose de CrowdSec, añadir un bind mount de solo lectura. Sustituir `HOST_LOG_DIR` por la ruta `Source` real obtenida con `docker inspect`:

```yaml
services:
  crowdsec:
    volumes:
      - HOST_LOG_DIR:/var/log/zoraxy:ro
```

Mantener los volúmenes actuales de datos y configuración de CrowdSec. No montar el socket Docker completo en CrowdSec solo para leer estos logs.

### 3. Corregir el acquisition

En el archivo de adquisición de Zoraxy dentro de CrowdSec (normalmente `/etc/crowdsec/acquis.d/zoraxy.yaml`), usar el destino del bind mount:

```yaml
filenames:
  - /var/log/zoraxy/zr_*.log
labels:
  type: zoraxy
```

Eliminar la adquisición antigua que apunta a `/opt/zoraxy/log/zr_*.log` para no mantener una fuente rota en paralelo.

Instalar la colección que incluye el parser `Raithmir/zoraxy-logs` y los escenarios HTTP:

```bash
docker exec crowdsec cscli collections install Raithmir/zoraxy
```

La colección/parser está pensado para el formato de logs de Zoraxy 3.2.0 o posterior. Comprobar la versión de Zoraxy antes de actualizar el parser. Aplicar los cambios recreando o reiniciando el contenedor CrowdSec según cómo se gestione ese proyecto en Arcane.

### 4. Mantener la API LAPI solo en la red Docker

El bouncer y CrowdSec deben compartir una red Docker definida por el usuario. La dirección del API dentro de esa red es:

```text
http://crowdsec:8080
```

En el proyecto CrowdSec, eliminar el puerto publicado del host:

```yaml
# Quitar:
ports:
  - "8019:8080"
```

El puerto 8080 debe quedar accesible solo entre contenedores de la red. El plugin de Zoraxy no necesita el puerto host 8019.

### 5. Configuración del plugin instalado en Zoraxy

Conservar la clave de bouncer ya registrada si sigue siendo válida. No ponerla en Git, documentación, capturas o mensajes. El `config.yaml` del plugin debe tener esta estructura (usar la clave real ya existente, no el texto de ejemplo):

```yaml
api_key: "<CLAVE_BOUNCER_EXISTENTE>"
agent_url: "http://crowdsec:8080"
stream_update_frequency: 10s
log_level: warning
is_proxied_behind_cloudflare: false
```

`is_proxied_behind_cloudflare` debe permanecer en `false` mientras el DNS de Cloudflare esté en modo DNS-only (sin proxy naranja). Cambiarlo solo si el tráfico pasa realmente por el proxy de Cloudflare.

Reiniciar el plugin desde Zoraxy después de editar el archivo. El log del bouncer debería seguir mostrando consultas correctas a `/v1/decisions/stream`.

### 6. Activar la protección por etiquetas en Zoraxy

El bouncer es un *Dynamic Capture Plugin*: que aparezca como activo no significa que proteja automáticamente todos los hosts.

En el panel de Zoraxy:

1. Abrir la gestión de Plugins y crear/seleccionar una etiqueta, por ejemplo `protected`.
2. Asignar el plugin CrowdSec a esa etiqueta/grupo.
3. Asignar esa misma etiqueta a cada proxy host que se quiera proteger.
4. Guardar y comprobar las estadísticas del plugin: debe aumentar el contador de peticiones procesadas para esos hosts.

El plugin actual aplica decisiones de ban. No proporciona CAPTCHA. Al ser un plugin de captura dinámica, no puede interceptar rutas que otro plugin estático ya haya capturado y no debe considerarse un reemplazo de la autenticación de los paneles.

## Verificación después de aplicar

En Atlas:

```bash
docker exec crowdsec cscli metrics show acquisition
docker exec crowdsec cscli bouncers list
docker exec crowdsec cscli decisions list
```

La fuente de Zoraxy debe mostrar líneas leídas/procesadas y no debe aparecer el aviso `No matching files for pattern`. En la lista de bouncers debe figurar el bouncer de Zoraxy con conexión reciente. Después, generar tráfico contra un host etiquetado y comprobar el contador del plugin.

Para verificar los filtros Docker:

```bash
sudo iptables -vnL DOCKER-USER
sudo ip6tables -vnL DOCKER-USER
```

No publicar la API de CrowdSec ni la API RPC de IPFS en Internet. El puerto 5553 es la API administrativa de Kubo; mantenerla en la red interna salvo que exista una necesidad explícita y una capa de autenticación/protección adicional.

## Referencias

- [CrowdSec Docker datasource](https://docs.crowdsec.net/docs/data_sources/docker/)
- [CrowdSec acquisition sources](https://docs.crowdsec.net/docs/log_processor/data_sources/intro/)
- [Zoraxy + CrowdSec: guía de adquisición y parser](https://github.com/tobychui/zoraxy/discussions/338)
- [Zoraxy CrowdSec Bouncer: instalación, etiquetas y configuración](https://github.com/AnthonyMichaelTDM/zoraxy_crowdsec_bouncer)
- [Arcane: Docker socket proxy](https://getarcane.app/docs/security/socket-proxy)
